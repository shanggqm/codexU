// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::path::PathBuf;
use std::sync::Arc;

use tauri::Manager;
use tracing::{info, warn};

mod app_state;
mod commands;
mod tray;

use app_state::AppState;

const BACKGROUND_CAPTURE_ARGUMENT: &str = "--codexu-native-capture-background";
const CAPTURE_APP_DATA_DIR_ENV: &str = "CODEXU_CAPTURE_APP_DATA_DIR";

fn is_background_capture() -> bool {
    std::env::args().any(|argument| argument == BACKGROUND_CAPTURE_ARGUMENT)
}

fn capture_app_data_dir() -> std::io::Result<PathBuf> {
    let path = std::env::var_os(CAPTURE_APP_DATA_DIR_ENV)
        .map(PathBuf::from)
        .ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("{CAPTURE_APP_DATA_DIR_ENV} is required for native capture"),
            )
        })?;
    if !path.is_absolute() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("{CAPTURE_APP_DATA_DIR_ENV} must be an absolute path"),
        ));
    }
    Ok(path)
}

#[cfg(windows)]
fn prepare_background_capture_window(window: &tauri::WebviewWindow) {
    use std::ffi::c_void;

    #[link(name = "user32")]
    extern "system" {
        fn GetWindowLongPtrW(hwnd: *mut c_void, index: i32) -> isize;
        fn SetWindowLongPtrW(hwnd: *mut c_void, index: i32, value: isize) -> isize;
    }

    const GWL_EXSTYLE: i32 = -20;
    const WS_EX_TOOLWINDOW: isize = 0x0000_0080;
    const WS_EX_NOACTIVATE: isize = 0x0800_0000;
    const WS_EX_APPWINDOW: isize = 0x0004_0000;

    let Ok(hwnd) = window.hwnd() else {
        return;
    };

    unsafe {
        let current = GetWindowLongPtrW(hwnd.0, GWL_EXSTYLE);
        let updated = (current | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) & !WS_EX_APPWINDOW;
        let _ = SetWindowLongPtrW(hwnd.0, GWL_EXSTYLE, updated);
    }
}

#[cfg(windows)]
fn show_background_capture_window(window: &tauri::WebviewWindow) {
    use std::ffi::c_void;

    #[link(name = "user32")]
    extern "system" {
        fn SetWindowPos(
            hwnd: *mut c_void,
            insert_after: *mut c_void,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            flags: u32,
        ) -> i32;
        fn ShowWindow(hwnd: *mut c_void, command: i32) -> i32;
    }

    const HWND_BOTTOM: isize = 1;
    const SW_SHOWNOACTIVATE: i32 = 4;
    const SWP_NOSIZE: u32 = 0x0001;
    const SWP_NOMOVE: u32 = 0x0002;
    const SWP_NOACTIVATE: u32 = 0x0010;
    const SWP_NOOWNERZORDER: u32 = 0x0200;
    const SWP_FRAMECHANGED: u32 = 0x0020;
    const SWP_SHOWWINDOW: u32 = 0x0040;

    let Ok(hwnd) = window.hwnd() else {
        return;
    };

    unsafe {
        let insert_after = HWND_BOTTOM as *mut c_void;
        let flags = SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_FRAMECHANGED;
        let _ = SetWindowPos(hwnd.0, insert_after, 0, 0, 0, 0, flags);
        let _ = ShowWindow(hwnd.0, SW_SHOWNOACTIVATE);
        let _ = SetWindowPos(
            hwnd.0,
            insert_after,
            0,
            0,
            0,
            0,
            SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW,
        );
    }
}

#[cfg(not(windows))]
fn prepare_background_capture_window(_window: &tauri::WebviewWindow) {}

#[cfg(not(windows))]
fn show_background_capture_window(_window: &tauri::WebviewWindow) {}

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Err(error) = tray::show_main_window(app) {
                warn!(error = %error, "Could not restore main window for secondary launch");
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let background_capture = is_background_capture();
            let app_data_dir = if background_capture {
                capture_app_data_dir()?
            } else {
                app.path().app_data_dir().map_err(|e| {
                    eprintln!("Failed to resolve app data dir: {}", e);
                    e
                })?
            };
            info!("App data dir: {}", app_data_dir.display());

            let state = Arc::new(AppState::new(app_data_dir));
            let initial_language = state
                .config
                .try_read()
                .map(|config| config.language.resolved(app_state::ResolvedLanguage::En))
                .unwrap_or(app_state::ResolvedLanguage::En);
            app.manage(state.clone());

            // Hide main window to tray on close instead of quitting.
            if let Some(window) = app.get_webview_window("main") {
                if background_capture {
                    // Keep the capture window non-activating before revealing it.
                    // Calling Tauri's asynchronous `show` here can use an
                    // activating Win32 show path before z-order correction.
                    prepare_background_capture_window(&window);
                    show_background_capture_window(&window);
                } else {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
                let window_clone = window.clone();
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        tray::hide_to_tray(&window_clone);
                        api.prevent_close();
                    }
                });
            }

            tray::setup_tray(app.handle(), initial_language)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::usage::get_local_usage,
            commands::usage::refresh_usage,
            commands::usage::clear_cache,
            commands::settings::get_settings,
            commands::settings::set_settings,
            commands::settings::open_settings_window,
            commands::settings::sync_runtime_language,
            tray_show_main_window,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[tauri::command]
fn tray_show_main_window(app: tauri::AppHandle) -> Result<(), String> {
    tray::show_main_window(&app)
}
