use std::path::Path;
use tokio::io::AsyncWriteExt;

use super::common::{fingerprint_for, CodexRolloutIndexEntry, FileFingerprint};

/// A failed read is never an empty or complete history. Messages deliberately
/// omit source paths, raw lines and low-level operating-system diagnostics.
#[derive(Debug, thiserror::Error)]
pub enum HistoryReadError {
    #[error("Local history is temporarily unreadable. Refresh to retry.")]
    Unavailable,
    #[error("Local history contains an incomplete or invalid record. Refresh to retry.")]
    InvalidRecord,
    #[error("Local history changed while being read. Refresh to retry.")]
    SourceChanged,
    #[error("Local history index is in use. Refresh to retry.")]
    IndexBusy,
    #[error("Local history cache has reached its space budget. Refresh to retry.")]
    CacheFull,
    #[error("Local history processing exceeded its resource budget. Refresh to retry.")]
    ResourceLimited,
    #[error("Local history index could not be written. Refresh to retry.")]
    CacheUnavailable,
}

pub const RETAINED_HISTORY_MESSAGE: &str =
    "Local history could not be read completely; showing the last complete history. Refresh to retry.";

pub async fn ensure_file_unchanged(
    path: &Path,
    expected: Option<&FileFingerprint>,
) -> Result<(), HistoryReadError> {
    let actual = fingerprint_for(path)
        .await
        .ok_or(HistoryReadError::Unavailable)?;
    if Some(&actual) != expected {
        return Err(HistoryReadError::SourceChanged);
    }
    Ok(())
}

pub async fn ensure_history_unchanged(
    index: &[CodexRolloutIndexEntry],
) -> Result<(), HistoryReadError> {
    for entry in index {
        ensure_file_unchanged(&entry.path, entry.fingerprint.as_ref()).await?;
    }
    Ok(())
}

/// A failed cache write must not truncate a previously complete cache.
pub async fn write_cache_atomically(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| std::io::Error::from(std::io::ErrorKind::InvalidInput))?;
    tokio::fs::create_dir_all(parent).await?;
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(std::io::Error::other)?
        .as_nanos();
    let temporary = parent.join(format!(".cache-{}-{nonce}.tmp", std::process::id()));
    let mut file = tokio::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .await?;
    let result = async {
        file.write_all(data).await?;
        file.flush().await?;
        drop(file);
        tokio::fs::rename(&temporary, path).await
    }
    .await;
    if result.is_err() {
        let _ = tokio::fs::remove_file(&temporary).await;
    }
    result
}
