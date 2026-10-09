use tauri::{AppHandle, Emitter, State};
use tracing::warn;

#[tauri::command]
pub async fn get_local_usage(
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<Option<codexu_core::models::CodexDashboardSnapshot>, String> {
    let config = state.config.read().await;
    let max_age = config.refresh_interval_secs;
    drop(config);
    state.get_usage(max_age).await.map_err(|e| {
        warn!(error = %e, "Failed to load local usage snapshot");
        "Failed to load local usage snapshot".to_string()
    })
}

#[tauri::command]
pub async fn refresh_usage(
    app: AppHandle,
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<Option<codexu_core::models::CodexDashboardSnapshot>, String> {
    let usage = state.refresh_usage().await.map_err(|e| {
        warn!(error = %e, "Failed to refresh local usage snapshot");
        "Failed to refresh local usage snapshot".to_string()
    })?;
    let _ = app.emit("usage:updated", ());
    Ok(usage)
}

#[tauri::command]
pub async fn clear_cache(
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<(), String> {
    crate::app_state::clear_cache(&state).await.map_err(|e| {
        warn!(error=%e,"Failed to clear local history cache");
        "Failed to clear local history cache".to_string()
    })
}
