use std::collections::HashMap;

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::codex_transcript::{
    codex_date_value, codex_f64_value, codex_string_value, codex_task_timestamp_value,
    parse_derived_task_started_at, safe_skill_loads_from_tool_payload, CodexSkillLoad,
    CodexTranscriptSummary, CodexUsageDelta,
};
use super::common::CodexTaskInterval;
use super::history_integrity::HistoryReadError;
use crate::models::{LeadershipEvidenceQuality, TokenBreakdown};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct ParserState {
    pub summary: CodexTranscriptSummary,
    pub cumulative: Option<TokenBreakdown>,
    pub started_tasks: HashMap<String, DateTime<Utc>>,
    pub parent_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum Fact {
    Usage {
        delta: CodexUsageDelta,
        signature: String,
    },
    Tool {
        name: String,
        skills: Vec<CodexSkillLoad>,
    },
    Interval(CodexTaskInterval),
}

impl ParserState {
    pub fn new(path: &str, fallback_session: String) -> Self {
        Self {
            summary: CodexTranscriptSummary {
                file_path: path.to_string(),
                session_id: fallback_session,
                project_path: String::new(),
                model: None,
                last_active_at: None,
                deltas: vec![],
                tool_calls: HashMap::new(),
                skill_loads: vec![],
                task_intervals: vec![],
            },
            cumulative: None,
            started_tasks: HashMap::new(),
            parent_id: None,
        }
    }

    pub fn consume(
        &mut self,
        db: &Connection,
        source: i64,
        offset: i64,
        line: &[u8],
    ) -> anyhow::Result<()> {
        if line.iter().all(u8::is_ascii_whitespace) {
            return Ok(());
        }
        let object: Value =
            serde_json::from_slice(line).map_err(|_| HistoryReadError::InvalidRecord)?;
        if !object.is_object() {
            return Err(HistoryReadError::InvalidRecord.into());
        }
        let kind = object.get("type").and_then(Value::as_str);
        let Some(payload) = object.get("payload").filter(|p| p.is_object()) else {
            return Ok(());
        };
        let timestamp = codex_date_value(object.get("timestamp"))
            .or_else(|| codex_date_value(payload.get("timestamp")))
            .ok_or(HistoryReadError::InvalidRecord)?;
        self.summary.last_active_at = Some(
            self.summary
                .last_active_at
                .map_or(timestamp, |d| d.max(timestamp)),
        );
        match kind {
            Some("session_meta") => {
                if let Some(id) = codex_string_value(payload.get("id")) {
                    self.summary.session_id = id;
                }
                if let Some(cwd) = codex_string_value(payload.get("cwd")) {
                    self.summary.project_path = cwd;
                }
                self.parent_id = codex_string_value(payload.get("forked_from_id"));
            }
            Some("turn_context") => {
                if let Some(cwd) = codex_string_value(payload.get("cwd")) {
                    self.summary.project_path = cwd;
                }
                if let Some(model) = codex_string_value(payload.get("model")) {
                    self.summary.model = Some(model.clone());
                    if let Some(turn) = codex_string_value(payload.get("turn_id")) {
                        db.execute("INSERT INTO turn_model(source,byte_offset,turn_id,model) VALUES(?1,?2,?3,?4)",params![source,offset,turn,model])?;
                    }
                }
            }
            Some("response_item") => {
                let payload_kind = payload.get("type").and_then(Value::as_str);
                if matches!(payload_kind, Some("function_call" | "custom_tool_call")) {
                    let name = codex_string_value(payload.get("name")).unwrap_or_default();
                    {
                        let skills = safe_skill_loads_from_tool_payload(payload, Some(timestamp));
                        if name.is_empty() && skills.is_empty() {
                            return Ok(());
                        }
                        let call = codex_string_value(payload.get("call_id"))
                            .unwrap_or_else(|| name.clone());
                        insert_fact(
                            db,
                            source,
                            offset,
                            "tool",
                            &format!("tool:{timestamp}:{call}"),
                            &Fact::Tool { name, skills },
                        )?;
                    }
                }
            }
            Some("event_msg") => match payload.get("type").and_then(Value::as_str) {
                Some("task_started") => {
                    if let (Some(turn), Some(start)) = (
                        codex_string_value(payload.get("turn_id")),
                        codex_task_timestamp_value(payload.get("started_at")),
                    ) {
                        self.started_tasks.insert(turn, start);
                        if self.started_tasks.len() > 1024 {
                            return Err(HistoryReadError::ResourceLimited.into());
                        }
                    }
                }
                Some("task_complete") => {
                    let turn = codex_string_value(payload.get("turn_id"));
                    let Some(end) = codex_task_timestamp_value(payload.get("completed_at")) else {
                        return Ok(());
                    };
                    let factual = turn.as_ref().and_then(|id| self.started_tasks.remove(id));
                    let derived = codex_f64_value(payload.get("duration_ms"))
                        .and_then(|ms| parse_derived_task_started_at(end, Some(ms)));
                    if let Some(start) = factual.or(derived).filter(|start| *start < end) {
                        let interval = CodexTaskInterval {
                            turn_id: turn.clone(),
                            started_at: start,
                            ended_at: end,
                            quality: if factual.is_some() {
                                LeadershipEvidenceQuality::Fact
                            } else {
                                LeadershipEvidenceQuality::Derived
                            },
                        };
                        insert_fact(
                            db,
                            source,
                            offset,
                            "interval",
                            &format!("interval:{start}:{end}:{turn:?}"),
                            &Fact::Interval(interval),
                        )?;
                    }
                }
                Some("token_count") => {
                    let Some(info) = payload.get("info").filter(|p| p.is_object()) else {
                        return Ok(());
                    };
                    let cumulative = info.get("total_token_usage").filter(|p| p.is_object());
                    let last = info.get("last_token_usage").filter(|p| p.is_object());
                    let Some(tokens) = normalize_counter(cumulative, last, &mut self.cumulative)
                    else {
                        return Ok(());
                    };
                    let turn = codex_string_value(payload.get("turn_id"));
                    let model = if let Some(ref turn) = turn {
                        db.query_row("SELECT model FROM turn_model WHERE source=?1 AND turn_id=?2 AND byte_offset<=?3 ORDER BY byte_offset DESC LIMIT 1",params![source,turn,offset],|r|r.get::<_,String>(0)).optional()?.or_else(||self.summary.model.clone())
                    } else {
                        self.summary.model.clone()
                    };
                    let signature = serde_json::to_string(&(
                        counter_identity(cumulative),
                        counter_identity(last),
                    ))?;
                    let key = format!("usage:{timestamp}:{turn:?}:{signature}");
                    let delta = CodexUsageDelta {
                        turn_id: Some(key.clone()),
                        date: timestamp,
                        tokens,
                        model,
                        project_path: self.summary.project_path.clone(),
                        session_id: self.summary.session_id.clone(),
                    };
                    insert_fact(
                        db,
                        source,
                        offset,
                        "usage",
                        &key,
                        &Fact::Usage { delta, signature },
                    )?;
                }
                _ => {}
            },
            _ => {}
        }
        Ok(())
    }
}

fn insert_fact(
    db: &Connection,
    source: i64,
    offset: i64,
    kind: &str,
    key: &str,
    fact: &Fact,
) -> anyhow::Result<()> {
    db.execute("INSERT OR IGNORE INTO fact(source,byte_offset,kind,event_key,payload) VALUES(?1,?2,?3,?4,?5)",params![source,offset,kind,key,serde_json::to_string(fact)?])?;
    Ok(())
}

fn number(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(|v| {
        v.as_i64()
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    })
}

fn counter_identity(value: Option<&Value>) -> Vec<Option<i64>> {
    [
        "input_tokens",
        "cached_input_tokens",
        "output_tokens",
        "reasoning_output_tokens",
        "total_tokens",
    ]
    .into_iter()
    .map(|key| value.and_then(|v| number(v, key)))
    .collect()
}

fn sample(value: &Value, previous: &TokenBreakdown) -> Option<TokenBreakdown> {
    let numbers = counter_identity(Some(value));
    if numbers.iter().flatten().any(|n| *n < 0) || numbers.iter().all(Option::is_none) {
        return None;
    }
    let input = number(value, "input_tokens").unwrap_or(previous.input_tokens);
    let output = number(value, "output_tokens").unwrap_or(previous.output_tokens);
    Some(TokenBreakdown {
        input_tokens: input,
        cached_input_tokens: number(value, "cached_input_tokens")
            .unwrap_or(previous.cached_input_tokens)
            .min(input),
        output_tokens: output,
        reasoning_output_tokens: number(value, "reasoning_output_tokens")
            .unwrap_or(previous.reasoning_output_tokens)
            .min(output),
        total_tokens: number(value, "total_tokens").unwrap_or(input.saturating_add(output)),
    })
}

fn normalize_counter(
    cumulative: Option<&Value>,
    last: Option<&Value>,
    state: &mut Option<TokenBreakdown>,
) -> Option<TokenBreakdown> {
    let last = last
        .and_then(|v| sample(v, &TokenBreakdown::ZERO))
        .filter(|v| !v.is_zero());
    let Some(raw) = cumulative else {
        return last;
    };
    let previous = state.clone().unwrap_or_default();
    let Some(observed) = sample(raw, &previous) else {
        return last;
    };
    if state.is_none()
        || (number(raw, "total_tokens").is_some_and(|n| n < previous.total_tokens)
            && number(raw, "input_tokens").is_some_and(|n| n < previous.input_tokens))
    {
        *state = Some(observed.clone());
        return last.or(Some(observed)).filter(|v| !v.is_zero());
    }
    let high = TokenBreakdown {
        input_tokens: previous.input_tokens.max(observed.input_tokens),
        cached_input_tokens: previous
            .cached_input_tokens
            .max(observed.cached_input_tokens),
        output_tokens: previous.output_tokens.max(observed.output_tokens),
        reasoning_output_tokens: previous
            .reasoning_output_tokens
            .max(observed.reasoning_output_tokens),
        total_tokens: previous.total_tokens.max(observed.total_tokens),
    };
    let total = high.total_tokens - previous.total_tokens;
    let output = (high.output_tokens - previous.output_tokens).min(total);
    let input = (high.input_tokens - previous.input_tokens).min(total - output);
    let delta = TokenBreakdown {
        input_tokens: input,
        cached_input_tokens: (high.cached_input_tokens - previous.cached_input_tokens).min(input),
        output_tokens: output,
        reasoning_output_tokens: (high.reasoning_output_tokens - previous.reasoning_output_tokens)
            .min(output),
        total_tokens: total,
    };
    *state = Some(high);
    if delta.is_zero() {
        None
    } else {
        last.or(Some(delta))
    }
}
