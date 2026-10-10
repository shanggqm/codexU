//! Explicit, loopback-only practical acceptance harness; compiled only as an ignored test.
use super::*;
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

async fn seed(base: &Path) -> Arc<AppState> {
    std::fs::create_dir_all(base.join("root/sessions")).unwrap();
    std::fs::create_dir_all(base.join("root/automations")).unwrap();
    super::tests::write_history_fixture(&base.join("root/sessions/rollout.jsonl"), 300);
    let state = Arc::new(AppState::new(base.join("app")));
    state
        .update_config(|c| {
            c.codex_root = base.join("root");
            c.cache_dir = base.join("cache");
            c.language = InterfaceLanguage::En;
            c.theme = ThemeMode::Light;
        })
        .await
        .unwrap();
    set_quota(&state).await;
    state.refresh_usage().await.unwrap();
    // A known prior leadership value tests persistence, not the score algorithm.
    {
        let mut cached = state.snapshot.write().await;
        let d = cached.as_mut().unwrap().dashboard.as_mut().unwrap();
        d.leadership.score = Some(67);
        crate::history_summary::save(
            &state.app_data_dir,
            &base.join("root"),
            &base.join("cache"),
            d,
        )
        .await
        .unwrap();
    }
    state
}

async fn set_quota(state: &AppState) {
    let mut quota = CodexAppServerQuotaSnapshot::unavailable();
    quota.quota_read_succeeded = true;
    quota.five_hour_quota = Some(codexu_core::models::RateWindow {
        used_percent: 17.0,
        window_duration_mins: Some(300),
        resets_at: None,
    });
    *state.test_quota.write().await = Some(quota);
}

#[tokio::test]
#[ignore = "Explicit synthetic AppState/HTTP acceptance harness; no native window or account access"]
async fn live_refresh_harness() {
    let base = PathBuf::from(
        std::env::var_os("CODEXU_REFRESH_HARNESS_ROOT").expect("owned harness root required"),
    );
    let expected = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../../.workblock/runtime/CODEXU-015/harness");
    std::fs::create_dir_all(&expected).unwrap();
    assert_eq!(
        base.canonicalize().unwrap(),
        expected.canonicalize().unwrap()
    );
    let seeded = seed(&base).await;
    let restarted = Arc::new(AppState::new(seeded.app_data_dir.clone()));
    set_quota(&restarted).await;
    restarted
        .branch_controls
        .write()
        .await
        .insert("history".into(), (5000, false));
    let state = Arc::new(RwLock::new(restarted));
    let shutdown = Arc::new(tokio::sync::Notify::new());
    let listener = TcpListener::bind(("127.0.0.1", 14815)).await.unwrap();
    println!("REFRESH_HARNESS_READY 127.0.0.1:14815 synthetic-only");
    loop {
        tokio::select! {
            _=shutdown.notified()=>break,
            accepted=listener.accept()=>{
                let (socket,_)=accepted.unwrap(); let state=state.clone(); let shutdown=shutdown.clone(); let base=base.clone();
                tokio::spawn(async move { if let Err(e)=serve(socket,state,shutdown,base).await { eprintln!("harness: {e}"); } });
            }
        }
    }
}

async fn serve(
    mut socket: TcpStream,
    shared: Arc<RwLock<Arc<AppState>>>,
    shutdown: Arc<tokio::sync::Notify>,
    base: PathBuf,
) -> anyhow::Result<()> {
    let mut bytes = Vec::new();
    let mut buffer = [0; 4096];
    let (start, length) = loop {
        let read =
            tokio::time::timeout(std::time::Duration::from_secs(5), socket.read(&mut buffer))
                .await??;
        anyhow::ensure!(read > 0, "request ended");
        bytes.extend_from_slice(&buffer[..read]);
        anyhow::ensure!(bytes.len() < 65536, "request budget");
        if let Some(end) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
            let header = String::from_utf8_lossy(&bytes[..end]);
            let length = header
                .lines()
                .find_map(|line| {
                    line.to_ascii_lowercase()
                        .strip_prefix("content-length:")
                        .map(str::trim)
                        .and_then(|v| v.parse::<usize>().ok())
                })
                .unwrap_or(0);
            if bytes.len() >= end + 4 + length {
                break (end + 4, length);
            }
        }
    };
    let result = if bytes.starts_with(b"OPTIONS ") {
        json!(null)
    } else {
        let request: Value = serde_json::from_slice(&bytes[start..start + length])?;
        let command = request["command"].as_str().unwrap_or("");
        let state = shared.read().await.clone();
        match command {
            "get_local_usage" => {
                state.request_refresh(false, 60).await;
                serde_json::to_value(state.current_view().await)?
            }
            "get_usage_state" => serde_json::to_value(state.current_view().await)?,
            "refresh_usage" => {
                state.request_refresh(true, 0).await;
                serde_json::to_value(state.current_view().await)?
            }
            "get_settings" => {
                let mut value = serde_json::to_value(state.config.read().await.clone())?;
                value["app_data_dir"] = json!(state.app_data_dir);
                value
            }
            "set_settings" => {
                let language = request["args"]["req"]["language"].as_str().unwrap_or("en");
                let config = state
                    .update_config(|c| {
                        c.language = if language == "zh-Hans" {
                            InterfaceLanguage::ZhHans
                        } else {
                            InterfaceLanguage::En
                        }
                    })
                    .await?;
                serde_json::to_value(config)?
            }
            "sync_runtime_language" => json!(null),
            "__events" => {
                let mut changes = state.subscribe_changes();
                let last = request["args"]["revision"].as_u64().unwrap_or(0);
                if *changes.borrow() == last {
                    let _ =
                        tokio::time::timeout(std::time::Duration::from_secs(3), changes.changed())
                            .await;
                }
                json!({"revision":*changes.borrow_and_update()})
            }
            "__scenario" => {
                let mode = request["args"]["mode"].as_str().unwrap_or("recover");
                let guard = state.refresh_lock.lock().await;
                drop(guard);
                if mode == "restart" || mode == "cold" {
                    if mode == "cold" {
                        clear_cache(&state).await?;
                    }
                    let next = Arc::new(AppState::new(state.app_data_dir.clone()));
                    set_quota(&next).await;
                    next.branch_controls
                        .write()
                        .await
                        .insert("history".into(), (5000, false));
                    *shared.write().await = next;
                } else {
                    state.branch_controls.write().await.clear();
                    if let Some(branch) = mode.strip_suffix("-slow") {
                        state
                            .branch_controls
                            .write()
                            .await
                            .insert(branch.into(), (5000, false));
                    }
                    if let Some(branch) = mode.strip_suffix("-fail") {
                        state
                            .branch_controls
                            .write()
                            .await
                            .insert(branch.into(), (300, true));
                    }
                    if mode == "source" {
                        let root = base.join("second");
                        std::fs::create_dir_all(root.join("sessions"))?;
                        super::tests::write_history_fixture(&root.join("sessions/new.jsonl"), 50);
                        state.update_config(|c| c.codex_root = root).await?;
                    }
                    if mode == "clear" {
                        clear_cache(&state).await?;
                    }
                }
                json!({"ok":true})
            }
            "__shutdown" => {
                shutdown.notify_one();
                json!({"ok":true})
            }
            _ => anyhow::bail!("unknown harness command"),
        }
    };
    let body = serde_json::to_vec(&result)?;
    let header=format!("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: http://127.0.0.1:14816\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: content-type\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",body.len());
    socket.write_all(header.as_bytes()).await?;
    socket.write_all(&body).await?;
    Ok(())
}
