import { useEffect } from 'react';
import { Activity, CircleDashed } from 'lucide-react';
import { Header } from '../components/Header';
import { DashboardHome } from '../components/DashboardHome';
import { RefreshStatus } from '../components/RefreshStatus';
import { useSettings } from '../hooks/useSettings';
import { useUsage } from '../hooks/useUsage';
import { applyAppTheme } from '../utils/appTheme';
import { DEFAULT_PALETTE_ID } from '../utils/paletteCatalog';
import { useI18n } from '../i18n/I18nProvider';

export function Dashboard() {
  const { t } = useI18n();
  const { dashboard, status, loading, error, refresh } = useUsage();
  const { settings, update } = useSettings();

  useEffect(() => {
    applyAppTheme(
      settings?.config.theme ?? 'system',
      settings?.config.palette_id ?? DEFAULT_PALETTE_ID,
    );
  }, [settings?.config.theme, settings?.config.palette_id]);

  const localUsage = dashboard?.codex?.snapshot?.local ?? null;
  const lastUpdated =
    status ? status.history.updated_at : dashboard?.codex?.snapshot?.refreshed_at ?? dashboard?.refreshed_at ?? localUsage?.last_updated_at ?? null;
  const messages = dashboard?.messages.filter(message => !status || !message.startsWith('Local history ')) ?? [];
  const quotaStatus = dashboard?.codex?.status ?? 'local_only';
  const quotaStatusLabel =
    quotaStatus === 'available'
      ? t('dashboard.status.officialQuotaActive')
      : quotaStatus === 'stale'
        ? t('dashboard.status.officialQuotaLastVerified')
        : t('dashboard.status.checkingOfficialQuota');
  const quotaStatusClass =
    quotaStatus === 'available'
      ? 'bg-status-ok/12 text-status-ok border-status-ok/30'
      : 'bg-status-warn/12 text-status-warn border-status-warn/30';

  const handleThemeChange = async (theme: 'system' | 'light' | 'dark') => {
    await update({ theme });
    applyAppTheme(theme, settings?.config.palette_id ?? DEFAULT_PALETTE_ID);
  };

  if (error && !dashboard) {
    return (
      <div className="h-full flex flex-col windows-glass-page">
        <Header
          lastUpdated={null}
          theme={settings?.config.theme ?? 'system'}
          onThemeChange={handleThemeChange}
          onRefresh={refresh}
          refreshing={loading}
        />
        <div className="flex-1 flex items-center justify-center p-6">
          <div className="glass-panel p-6 max-w-md border-status-error/30 bg-status-error/8">
            <h2 className="text-lg font-semibold text-status-error mb-2">{t('dashboard.errors.failedToLoadUsage')}</h2>
            <p className="text-sm opacity-90 text-status-error/90">{error}</p>
            <button
              onClick={refresh}
              className="mt-4 px-4 py-2 rounded-full glass-button-solid text-sm"
            >
              {t('common.retry')}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col windows-glass-page">
      <Header
        lastUpdated={lastUpdated}
        theme={settings?.config.theme ?? 'system'}
        onThemeChange={handleThemeChange}
        onRefresh={refresh}
        refreshing={loading}
      />

      <main className="flex-1 min-h-0 overflow-auto p-6 md:p-7">
        {!dashboard && (
          <div className="glass-panel p-6 mb-6" role="status" aria-live="polite">
            {loading ? (
              <>
                <h2 className="text-sm font-semibold text-primary">{t('dashboard.errors.loadingUsageData')}</h2>
                <p className="text-sm text-secondary mt-1">{t('dashboard.errors.collectingLocalSnapshots')}</p>
              </>
            ) : (
              <>
                <h2 className="text-sm font-semibold text-primary">{t('dashboard.errors.noUsageSnapshot')}</h2>
                <p className="text-sm text-secondary mt-1">
                  {t('dashboard.errors.noLocalUsage')}
                </p>
                <button
                  onClick={refresh}
                  className="mt-4 px-4 py-2 rounded-full glass-button-solid text-sm"
                >
                  {t('common.refreshNow')}
                </button>
              </>
            )}
          </div>
        )}

        <div className="max-w-6xl mx-auto w-full space-y-6">
          <div className="flex items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <span className={`inline-flex items-center gap-1.5 chip-like ${quotaStatusClass}`}>
                <Activity size={12} /> {quotaStatusLabel}
              </span>
              {localUsage ? <span className="text-xs text-tertiary">{t('dashboard.status.threads', { count: localUsage.thread_count })}</span> : null}
              {!localUsage ? (
                <span className="text-xs text-tertiary">
                  {dashboard ? t('dashboard.status.noLocalUsageDetails') : t('dashboard.status.waitingSnapshot')}
                </span>
              ) : null}
            </div>
            <span className="inline-flex items-center gap-1.5 chip-like text-xs text-secondary">
              <CircleDashed size={12} />
              {t('dashboard.status.lastUpdate', {
                time: lastUpdated ? new Date(lastUpdated).toLocaleTimeString() : t('dashboard.status.waiting'),
              })}
            </span>
          </div>
          <RefreshStatus status={status} />
          {error && dashboard ? <p className="text-xs text-status-warn" role="alert">{t('dashboard.refresh.connectionFailed')}</p> : null}
          {messages.length ? (
            <p className="text-xs text-tertiary mt-2">
              {t('dashboard.errors.status', { messages: messages.join(' · ') })}
            </p>
          ) : null}

          <DashboardHome
            snapshot={dashboard?.codex?.snapshot}
            quotaSourceLabel={dashboard?.codex?.quota_source_label}
            leadershipSignal={dashboard?.leadership ?? null}
            onQuotaRefresh={refresh}
          />
        </div>
      </main>
    </div>
  );
}
