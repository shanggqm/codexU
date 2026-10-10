export interface TokenBreakdown {
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
  reasoning_output_tokens: number;
  total_tokens: number;
}

export interface PricedTokenUsage {
  tokens: TokenBreakdown;
  estimated_cost_usd: number;
}

export interface DetailedUsage {
  today: PricedTokenUsage;
  seven_day: PricedTokenUsage;
  month: PricedTokenUsage;
  lifetime: PricedTokenUsage;
  parsed_file_count: number;
  token_event_count: number;
}

export type InferencePerformancePeriodId = 'today' | 'sevenDays' | 'twentyEightDays';

export interface InferencePerformanceGroup {
  id: string;
  model: string;
  effort: string;
  call_count: number;
  average_daily_call_count: number;
  average_duration_seconds: number;
  p50_duration_seconds: number;
  p90_duration_seconds: number;
  effective_output_tokens_per_second: number;
  output_tokens: number;
  reasoning_output_tokens: number;
}

export interface InferencePerformancePeriod {
  period: InferencePerformancePeriodId;
  coverage_day_count: number;
  groups: InferencePerformanceGroup[];
  total_call_count: number;
}

export interface InferencePerformanceHistory {
  recording_started_at: number;
  today: InferencePerformancePeriod | null;
  seven_days: InferencePerformancePeriod | null;
  twenty_eight_days: InferencePerformancePeriod | null;
}

export interface DailyTokenBucket {
  id: string;
  label: string;
  tokens: number;
}

export interface LocalThread {
  id: string;
  title: string;
  tokens: number;
  updated_at: number | null;
  model: string | null;
  cwd: string;
  archived: boolean;
}

export interface ProjectUsage {
  id: string;
  name: string;
  full_path: string;
  tokens: number;
  estimated_cost_usd: number | null;
  thread_count: number;
  last_active_at: number | null;
  source_quality: 'detailed' | 'approximate';
}

export interface ProjectBoard {
  recent_projects: ProjectUsage[];
  all_projects: ProjectUsage[];
}

export interface ToolUsage {
  id: string;
  name: string;
  category: string;
  call_count: number;
  estimated_tokens: number | null;
  estimated_cost_usd: number | null;
}

export interface SkillUsage {
  id: string;
  name: string;
  source_label: string;
  load_count: number;
  thread_count: number;
  last_loaded_at: number | null;
}

export interface UsageDayBucket {
  id: string;
  date: number;
  usage: PricedTokenUsage;
  source_quality: 'detailed' | 'approximate';
}

export interface UsageHeatmapDay {
  id: string;
  date: number;
  usage: PricedTokenUsage | null;
  is_future: boolean;
}

export interface UsageTrendSummary {
  seven_day: PricedTokenUsage;
  daily_average_tokens: number;
  peak_day: UsageDayBucket | null;
  change_percent: number | null;
  is_new_activity: boolean;
}

export interface ModelUsageTrend {
  id: string;
  model: string | null;
  day_buckets: UsageDayBucket[];
  summary: UsageTrendSummary;
  active_day_count: number;
}

export interface UsageTrend {
  day_buckets: UsageDayBucket[];
  heatmap_weeks: UsageHeatmapDay[][];
  heatmap_thresholds: number[];
  summary: UsageTrendSummary;
  model_trends: ModelUsageTrend[] | null;
  month: PricedTokenUsage;
  projected_month_cost_usd: number | null;
  active_day_count: number;
  source_quality: 'detailed' | 'approximate';
}

export interface TaskItem {
  id: string;
  code: string;
  title: string;
  detail: string;
  chip: string;
  updated_at: number | null;
  tokens: number | null;
  kind: string;
  thread_id: string | null;
  runtime_state: string;
  source_kind: string;
  display_state: string;
  state_basis: string;
  raw_status: string | null;
  next_run_at: number | null;
}

export interface TaskColumn {
  id: string;
  title: string;
  count: number;
  items: TaskItem[];
}

export interface TaskBoard {
  refreshed_at: number;
  columns: TaskColumn[];
}

export interface LeadershipWorker {
  id: string;
  runtime: string;
  kind: 'main' | 'subagent' | 'automation';
  project_id: string;
  project_name: string;
  parent_id: string | null;
}

export interface LeadershipInterval {
  id: string;
  worker_id: string;
  runtime: string;
  worker_kind: 'main' | 'subagent' | 'automation';
  project_id: string;
  start_at: number;
  end_at: number;
  quality: 'fact' | 'derived' | 'estimated';
  is_autonomous: boolean;
}

export interface LeadershipDimension {
  kind: 'span' | 'leverage' | 'orchestration' | 'autonomy';
  score: number;
  confidence: number;
  summary_value: number;
}

export interface LeadershipTitle {
  level: number;
  name: string;
  english_name: string;
  lower_bound: number;
  upper_bound: number;
}

export interface LeadershipDayPoint {
  day: number;
  agent_count: number;
  ai_hours: number;
  peak_concurrency: number;
}

export interface LeadershipProjectContribution {
  project_id: string;
  project_name: string;
  agent_count: number;
  ai_hours: number;
  autonomous_hours: number;
}

export interface LeadershipReport {
  period: string;
  score: number | null;
  core_score: number | null;
  title: LeadershipTitle | null;
  dimensions: LeadershipDimension[];
  maturity: number;
  evidence_coverage: number;
  active_day_count: number;
  agent_count: number | null;
  ai_hours: number | null;
  autonomous_hours: number | null;
  average_parallelism: number | null;
  peak_concurrency: number | null;
  project_count: number;
  daily_points: LeadershipDayPoint[];
  projects: LeadershipProjectContribution[];
}

export interface LeadershipDashboardSnapshot {
  model_version: string;
  refreshed_at: number;
  reports: LeadershipReport[];
}

export interface CodexLeadershipSignal {
  score: number | null;
  evidence_coverage: number;
  active_day_count: number;
  period: string;
  model_version: string;
  report: LeadershipDashboardSnapshot | null;
}

export interface LocalUsage {
  lifetime_tokens: number;
  today_tokens: number;
  seven_day_tokens: number;
  thread_count: number;
  last_updated_at: number | null;
  daily_buckets: DailyTokenBucket[];
  recent_threads: LocalThread[];
  detailed_usage: DetailedUsage | null;
  usage_trend: UsageTrend | null;
  inference_performance: InferencePerformanceHistory | null;
  project_board: ProjectBoard | null;
  tool_usages: ToolUsage[];
  skill_usages: SkillUsage[];
}

export interface RateWindow {
  used_percent: number;
  window_duration_mins: number | null;
  resets_at: number | null;
}

export interface AccountInfo {
  type: string;
  plan_type: string | null;
  email_present: boolean;
}

export interface UsageSnapshot {
  refreshed_at: number;
  account: AccountInfo;
  limit_id: string;
  limit_name: string;
  quota_read_succeeded: boolean;
  five_hour_quota: RateWindow | null;
  seven_day_quota: RateWindow | null;
  monthly_quota: RateWindow | null;
  local: LocalUsage | null;
  task_board: TaskBoard | null;
  messages: string[];
}

export type RuntimeScope = 'codex';

export type RuntimeMenuStatus = 'available' | 'local_only' | 'snapshot_needed' | 'stale' | 'unavailable';

export interface RuntimeUsageSnapshot {
  scope: RuntimeScope;
  snapshot: UsageSnapshot;
  status: RuntimeMenuStatus;
  quota_source_label: string;
  usage_source_label: string;
}

export interface CodexDashboardSnapshot {
  codex: RuntimeUsageSnapshot;
  leadership: CodexLeadershipSignal;
  refreshed_at: number;
  messages: string[];
}

export interface BranchRefreshState {
  phase: 'waiting' | 'loading' | 'current' | 'failed';
  has_data: boolean;
  restored: boolean;
  updated_at: number | null;
}

export interface DashboardView {
  dashboard: CodexDashboardSnapshot | null;
  refresh: {
    quota: BranchRefreshState;
    tasks: BranchRefreshState;
    history: BranchRefreshState;
    summary_write_failed: boolean;
  };
  revision: number;
}
