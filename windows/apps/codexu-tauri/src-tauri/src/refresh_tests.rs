use super::*;
use codexu_core::models::RateWindow;
use tempfile::{tempdir, TempDir};

async fn fixture() -> (TempDir, Arc<AppState>) {
    let temp = tempdir().unwrap();
    let state = Arc::new(AppState::new(temp.path().join("app")));
    let root = temp.path().join("root");
    std::fs::create_dir_all(root.join("sessions")).unwrap();
    std::fs::create_dir_all(root.join("automations")).unwrap();
    super::tests::write_history_fixture(&root.join("sessions/rollout.jsonl"), 300);
    state
        .update_config(|config| {
            config.codex_root = root;
            config.cache_dir = temp.path().join("cache");
        })
        .await
        .unwrap();
    *state.test_quota.write().await = Some(quota());
    (temp, state)
}

fn quota() -> CodexAppServerQuotaSnapshot {
    let mut value = CodexAppServerQuotaSnapshot::unavailable();
    value.quota_read_succeeded = true;
    value.five_hour_quota = Some(RateWindow {
        used_percent: 17.0,
        window_duration_mins: Some(300),
        resets_at: None,
    });
    value
}

async fn wait_for(
    state: &Arc<AppState>,
    predicate: impl Fn(&DashboardView) -> bool,
) -> DashboardView {
    tokio::time::timeout(std::time::Duration::from_secs(4), async {
        loop {
            let view = state.current_view().await;
            if predicate(&view) {
                return view;
            }
            tokio::time::sleep(std::time::Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("refresh observation timed out")
}

#[tokio::test]
async fn restart_shows_bounded_summary_before_history_and_preserves_independent_updates() {
    let (_temp, state) = fixture().await;
    state.refresh_usage().await.unwrap();
    {
        let mut cached = state.snapshot.write().await;
        let d = cached.as_mut().unwrap().dashboard.as_mut().unwrap();
        d.leadership.score = Some(67);
        d.leadership.evidence_coverage = 0.95;
        d.leadership.active_day_count = 14;
        crate::history_summary::save(
            &state.app_data_dir,
            &state.config.read().await.codex_root,
            &state.config.read().await.cache_dir,
            d,
        )
        .await
        .unwrap();
    }
    let saved = std::fs::read(state.app_data_dir.join("history-summary.json")).unwrap();
    assert!(saved.len() < 256 * 1024);
    let restarted = Arc::new(AppState::new(state.app_data_dir.clone()));
    *restarted.test_quota.write().await = Some(quota());
    restarted
        .branch_controls
        .write()
        .await
        .insert("history".into(), (500, false));
    let restored = restarted.current_view().await;
    let local = restored
        .dashboard
        .as_ref()
        .unwrap()
        .codex
        .snapshot
        .local
        .as_ref()
        .unwrap();
    assert_eq!(local.lifetime_tokens, 300);
    assert!(local.recent_threads.is_empty());
    assert!(restored.refresh.history.restored);
    assert_eq!(
        restored.dashboard.as_ref().unwrap().leadership.score,
        Some(67)
    );
    assert_eq!(
        restored
            .dashboard
            .as_ref()
            .unwrap()
            .leadership
            .evidence_coverage,
        0.95
    );
    assert!(restored
        .dashboard
        .unwrap()
        .codex
        .snapshot
        .five_hour_quota
        .is_none());
    restarted.request_refresh(true, 0).await;
    let early = wait_for(&restarted, |v| {
        v.refresh.quota.phase == RefreshPhase::Current
            && v.refresh.tasks.phase == RefreshPhase::Current
    })
    .await;
    assert_eq!(early.refresh.history.phase, RefreshPhase::Loading);
    let dashboard = early.dashboard.unwrap();
    assert_eq!(dashboard.codex.snapshot.local.unwrap().lifetime_tokens, 300);
    assert_eq!(
        dashboard
            .codex
            .snapshot
            .five_hour_quota
            .unwrap()
            .used_percent,
        17.0
    );
    let complete = wait_for(&restarted, |v| {
        v.refresh.history.phase == RefreshPhase::Current
    })
    .await;
    assert!(!complete.refresh.history.restored);
}

#[tokio::test]
async fn each_delayed_or_failed_branch_does_not_block_siblings_and_recovers() {
    for branch in ["quota", "tasks", "history"] {
        let (_temp, state) = fixture().await;
        state.refresh_usage().await.unwrap();
        let bytes = std::fs::read(state.app_data_dir.join("history-summary.json")).unwrap();
        state
            .branch_controls
            .write()
            .await
            .insert(branch.into(), (350, true));
        state.request_refresh(true, 0).await;
        let early = wait_for(&state, |v| {
            let delayed = match branch {
                "quota" => &v.refresh.quota,
                "tasks" => &v.refresh.tasks,
                _ => &v.refresh.history,
            };
            if delayed.phase != RefreshPhase::Loading {
                return false;
            }
            [
                ("quota", &v.refresh.quota),
                ("tasks", &v.refresh.tasks),
                ("history", &v.refresh.history),
            ]
            .iter()
            .all(|(name, s)| *name == branch || s.phase == RefreshPhase::Current)
        })
        .await;
        let delayed = match branch {
            "quota" => &early.refresh.quota,
            "tasks" => &early.refresh.tasks,
            _ => &early.refresh.history,
        };
        assert_eq!(delayed.phase, RefreshPhase::Loading);
        let failed = wait_for(&state, |v| {
            [&v.refresh.quota, &v.refresh.tasks, &v.refresh.history]
                .iter()
                .any(|s| s.phase == RefreshPhase::Failed)
        })
        .await;
        assert_eq!(
            failed
                .dashboard
                .unwrap()
                .codex
                .snapshot
                .local
                .unwrap()
                .lifetime_tokens,
            300
        );
        let _guard = state.refresh_lock.lock().await;
        drop(_guard);
        if branch == "history" {
            assert_eq!(
                std::fs::read(state.app_data_dir.join("history-summary.json")).unwrap(),
                bytes
            );
        }
        state.branch_controls.write().await.clear();
        state.request_refresh(true, 0).await;
        wait_for(&state, |v| {
            [&v.refresh.quota, &v.refresh.tasks, &v.refresh.history]
                .iter()
                .all(|s| s.phase == RefreshPhase::Current)
        })
        .await;
    }
}

#[tokio::test]
async fn cold_start_is_missing_not_zero_and_concurrent_requests_share_one_cycle() {
    let (_temp, state) = fixture().await;
    state
        .branch_controls
        .write()
        .await
        .insert("history".into(), (200, false));
    let initial = state.current_view().await;
    assert!(initial.dashboard.is_none());
    for _ in 0..20 {
        state.request_refresh(true, 0).await;
    }
    let loading = wait_for(&state, |v| v.refresh.history.phase == RefreshPhase::Loading).await;
    assert!(loading.dashboard.unwrap().codex.snapshot.local.is_none());
    wait_for(&state, |v| v.refresh.history.phase == RefreshPhase::Current).await;
    let _guard = state.refresh_lock.lock().await;
    assert_eq!(state.refresh_call_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn switching_source_during_delayed_history_cancels_old_generation_and_clear_removes_summary()
{
    let (temp, state) = fixture().await;
    state.refresh_usage().await.unwrap();
    state
        .branch_controls
        .write()
        .await
        .insert("history".into(), (300, false));
    state.request_refresh(true, 0).await;
    wait_for(&state, |v| v.refresh.history.phase == RefreshPhase::Loading).await;
    let new_root = temp.path().join("second");
    std::fs::create_dir_all(new_root.join("sessions")).unwrap();
    super::tests::write_history_fixture(&new_root.join("sessions/new.jsonl"), 50);
    state
        .update_config(|config| config.codex_root = new_root)
        .await
        .unwrap();
    assert!(state.current_view().await.dashboard.is_none());
    assert!(!state.app_data_dir.join("history-summary.json").exists());
    let final_view = wait_for(&state, |v| v.refresh.history.phase == RefreshPhase::Current).await;
    assert_eq!(
        final_view
            .dashboard
            .unwrap()
            .codex
            .snapshot
            .local
            .unwrap()
            .lifetime_tokens,
        50
    );
    let _guard = state.refresh_lock.lock().await;
    drop(_guard);
    clear_cache(&state).await.unwrap();
    assert!(state.current_view().await.dashboard.is_none());
    assert!(!state.app_data_dir.join("history-summary.json").exists());
    assert!(AppState::new(state.app_data_dir.clone())
        .snapshot
        .into_inner()
        .is_none());
}

#[tokio::test]
async fn corrupt_oversized_and_other_source_summaries_never_restore_and_save_failure_is_visible() {
    let (temp, state) = fixture().await;
    state.refresh_usage().await.unwrap();
    let summary = state.app_data_dir.join("history-summary.json");
    let saved = std::fs::read(&summary).unwrap();
    std::fs::write(&summary, b"{broken").unwrap();
    assert!(AppState::new(state.app_data_dir.clone())
        .snapshot
        .into_inner()
        .is_none());
    std::fs::write(&summary, vec![b' '; 256 * 1024 + 1]).unwrap();
    assert!(AppState::new(state.app_data_dir.clone())
        .snapshot
        .into_inner()
        .is_none());
    std::fs::write(&summary, &saved).unwrap();
    assert!(crate::history_summary::load(
        &state.app_data_dir,
        &temp.path().join("other"),
        &temp.path().join("cache")
    )
    .is_none());
    std::fs::remove_file(&summary).unwrap();
    std::fs::create_dir(&summary).unwrap();
    state.refresh_usage().await.unwrap();
    assert!(state.current_view().await.refresh.summary_write_failed);
    assert_eq!(
        state
            .current_view()
            .await
            .dashboard
            .unwrap()
            .codex
            .snapshot
            .local
            .unwrap()
            .lifetime_tokens,
        300
    );
}
