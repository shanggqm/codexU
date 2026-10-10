use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager};
use tracing::warn;

use crate::app_state::ResolvedLanguage;
use crate::commands::usage::refresh_usage;

struct TrayMenu {
    open: MenuItem<tauri::Wry>,
    settings: MenuItem<tauri::Wry>,
    refresh: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
}

struct TrayLabels {
    open: &'static str,
    settings: &'static str,
    refresh: &'static str,
    quit: &'static str,
}

pub fn setup_tray(app: &AppHandle, language: ResolvedLanguage) -> anyhow::Result<()> {
    let labels = labels_for(language);
    let open_i = MenuItem::with_id(app, "open", labels.open, true, None::<&str>)?;
    let settings_i = MenuItem::with_id(app, "settings", labels.settings, true, None::<&str>)?;
    let refresh_i = MenuItem::with_id(app, "refresh", labels.refresh, true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit_i = MenuItem::with_id(app, "quit", labels.quit, true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[&open_i, &settings_i, &refresh_i, &separator, &quit_i],
    )?;

    app.manage(TrayMenu {
        open: open_i.clone(),
        settings: settings_i.clone(),
        refresh: refresh_i.clone(),
        quit: quit_i.clone(),
    });

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .tooltip("codexU")
        .menu(&menu)
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                ..
            } = event
            {
                show_main_window_or_log(tray.app_handle());
            }
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => show_main_window_or_log(app),
            "settings" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    let _ = crate::commands::settings::open_settings_window(app).await;
                });
            }
            "refresh" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    let state = app.state::<std::sync::Arc<crate::app_state::AppState>>();
                    let _ = refresh_usage(state).await;
                });
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    Ok(())
}

pub fn update_labels(app: &AppHandle, language: ResolvedLanguage) {
    let labels = labels_for(language);
    if let Some(menu) = app.try_state::<TrayMenu>() {
        let _ = menu.open.set_text(labels.open);
        let _ = menu.settings.set_text(labels.settings);
        let _ = menu.refresh.set_text(labels.refresh);
        let _ = menu.quit.set_text(labels.quit);
    }
}

fn labels_for(language: ResolvedLanguage) -> TrayLabels {
    match language {
        ResolvedLanguage::ZhHans => TrayLabels {
            open: "打开仪表盘",
            settings: "设置",
            refresh: "刷新",
            quit: "退出",
        },
        ResolvedLanguage::En => TrayLabels {
            open: "Open Dashboard",
            settings: "Settings",
            refresh: "Refresh",
            quit: "Quit",
        },
    }
}

fn show_main_window_or_log(app: &AppHandle) {
    if let Err(error) = show_main_window(app) {
        warn!(error = %error, "Could not show main window from tray action");
    }
}

pub fn show_main_window(app: &AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window
            .show()
            .map_err(|e| format!("Failed to show main window: {}", e))?;
        window
            .set_focus()
            .map_err(|e| format!("Failed to focus main window: {}", e))?;
    } else {
        let window = tauri::WebviewWindowBuilder::from_config(
            app,
            &app.config()
                .app
                .windows
                .first()
                .cloned()
                .unwrap_or_default(),
        )
        .map_err(|e| format!("Failed to create main window builder: {}", e))?
        .build()
        .map_err(|e| format!("Failed to build main window: {}", e))?;
        window
            .show()
            .map_err(|e| format!("Failed to show rebuilt main window: {}", e))?;
        window
            .set_focus()
            .map_err(|e| format!("Failed to focus rebuilt main window: {}", e))?;
    }
    Ok(())
}

pub fn hide_to_tray(window: &tauri::WebviewWindow) {
    let _ = window.hide();
}
