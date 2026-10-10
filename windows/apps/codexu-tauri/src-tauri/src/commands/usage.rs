use tauri::State;
use tracing::warn;

#[tauri::command]
pub async fn get_local_usage(
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<crate::app_state::DashboardView, String> {
    let config = state.config.read().await;
    let max_age = config.refresh_interval_secs;
    drop(config);
    state.request_refresh(false, max_age).await;
    Ok(state.current_view().await)
}

#[tauri::command]
pub async fn get_usage_state(
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<crate::app_state::DashboardView, String> {
    Ok(state.current_view().await)
}

#[tauri::command]
pub async fn refresh_usage(
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<crate::app_state::DashboardView, String> {
    state.request_refresh(true, 0).await;
    Ok(state.current_view().await)
}

#[tauri::command]
pub async fn clear_cache(
    state: State<'_, std::sync::Arc<crate::app_state::AppState>>,
) -> Result<(), String> {
    crate::app_state::clear_cache(&state).await.map_err(|e| {
        warn!(error=%e,"Failed to clear local history cache");
        "Failed to clear local history cache".to_string()
    })?;
    state.request_refresh(true, 0).await;
    Ok(())
}
