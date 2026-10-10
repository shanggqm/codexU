use std::path::PathBuf;

use tauri::{AppHandle, Emitter, Manager, State};

use crate::app_state::{
    AppConfig, AppState, InterfaceLanguage, ResolvedLanguage, ThemeMode, TrayDensity,
};

#[derive(Debug, serde::Serialize)]
pub struct SettingsDto {
    #[serde(flatten)]
    pub config: AppConfig,
    pub app_data_dir: PathBuf,
}

#[tauri::command]
pub async fn open_settings_window(app: AppHandle) -> Result<(), String> {
    let app_state = app.state::<std::sync::Arc<AppState>>();
    let runtime_language = *app_state.runtime_language.read().await;

    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.set_title(settings_window_title(runtime_language));
        let _ = window.show();
        let _ = window.set_focus();
        return Ok(());
    }

    let window =
        tauri::WebviewWindowBuilder::new(&app, "settings", tauri::WebviewUrl::App("/".into()))
            .title(settings_window_title(runtime_language))
            .inner_size(540.0, 680.0)
            .resizable(false)
            .maximizable(false)
            .minimizable(false)
            .center()
            .build()
            .map_err(|e| format!("Failed to create settings window: {}", e))?;

    let theme = {
        let config = app_state.config.read().await;
        config.theme
    };
    apply_theme(&app, theme);
    let _ = window.show();
    let _ = window.set_focus();
    Ok(())
}

#[tauri::command]
pub async fn get_settings(
    state: State<'_, std::sync::Arc<AppState>>,
) -> Result<SettingsDto, String> {
    let config = state.config.read().await.clone();
    Ok(SettingsDto {
        config,
        app_data_dir: state.app_data_dir.clone(),
    })
}

#[derive(Debug, serde::Deserialize)]
pub struct UpdateSettingsRequest {
    pub codex_root: Option<PathBuf>,
    pub cache_dir: Option<PathBuf>,
    pub theme: Option<ThemeMode>,
    pub palette_id: Option<String>,
    pub refresh_interval_secs: Option<u64>,
    pub tray_density: Option<TrayDensity>,
    pub language: Option<InterfaceLanguage>,
}

#[tauri::command]
pub async fn set_settings(
    app: AppHandle,
    state: State<'_, std::sync::Arc<AppState>>,
    req: UpdateSettingsRequest,
) -> Result<AppConfig, String> {
    let config = state
        .update_config(|config| {
            if let Some(path) = req.codex_root {
                config.codex_root = path;
            }
            if let Some(path) = req.cache_dir {
                config.cache_dir = path;
            }
            if let Some(theme) = req.theme {
                config.theme = theme;
            }
            if let Some(palette_id) = req.palette_id {
                let palette_id = palette_id.trim();
                if !palette_id.is_empty() {
                    config.palette_id = palette_id.to_string();
                }
            }
            if let Some(interval) = req.refresh_interval_secs {
                config.refresh_interval_secs = interval.clamp(10, 3600);
            }
            if let Some(density) = req.tray_density {
                config.tray_density = density;
            }
            if let Some(language) = req.language {
                config.language = language;
            }
        })
        .await
        .map_err(|e| format!("Failed to save settings: {}", e))?;

    apply_theme(&app, config.theme);
    if config.language != InterfaceLanguage::Auto {
        let language = config.language.resolved(ResolvedLanguage::En);
        state.inner().set_runtime_language(language).await;
        apply_language(&app, language);
    }
    let _ = app.emit("settings:changed", config.clone());
    state
        .request_refresh(false, config.refresh_interval_secs)
        .await;
    Ok(config)
}

#[tauri::command]
pub async fn sync_runtime_language(
    app: AppHandle,
    state: State<'_, std::sync::Arc<AppState>>,
    language: ResolvedLanguage,
) -> Result<(), String> {
    state.inner().set_runtime_language(language).await;
    apply_language(&app, language);
    Ok(())
}

pub fn apply_language(app: &AppHandle, language: ResolvedLanguage) {
    crate::tray::update_labels(app, language);
    update_window_titles(app, language);
}

pub fn update_window_titles(app: &AppHandle, language: ResolvedLanguage) {
    if let Some(window) = app.get_webview_window("settings") {
        let _ = window.set_title(settings_window_title(language));
    }
}

fn settings_window_title(language: ResolvedLanguage) -> &'static str {
    match language {
        ResolvedLanguage::ZhHans => "设置 — codexU",
        ResolvedLanguage::En => "Settings — codexU",
    }
}

fn apply_theme(app: &AppHandle, theme: ThemeMode) {
    let windows = app.webview_windows();
    let dark = match theme {
        ThemeMode::System => {
            // Frontend will detect system preference on load.
            return;
        }
        ThemeMode::Light => false,
        ThemeMode::Dark => true,
    };
    for (_, window) in windows {
        let _ = window.eval(&format!(
            "document.documentElement.classList.remove('dark'); if ({}) document.documentElement.classList.add('dark');",
            dark
        ));
        let _ = window.eval(&format!(
            "window.__CODEXU_THEME__ = '{}'",
            if dark { "dark" } else { "light" }
        ));
    }
}
