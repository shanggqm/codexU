import type { BranchRefreshState, DashboardView } from '../types/models';
import { useI18n } from '../i18n/I18nProvider';

export function RefreshStatus({ status }: { status: DashboardView['refresh'] | null }) {
  const { t } = useI18n();
  if (!status) return null;
  const message = (state: BranchRefreshState) => {
    if (state.phase === 'failed') return state.has_data ? t('dashboard.refresh.failedRetained') : t('dashboard.refresh.failed');
    if (state.phase === 'loading') return state.has_data ? t('dashboard.refresh.updatingRetained') : t('dashboard.refresh.loading');
    if (state.restored) return t('dashboard.refresh.restored');
    if (state.phase === 'current') return state.has_data ? t('dashboard.refresh.current') : t('dashboard.refresh.empty');
    return t('dashboard.refresh.waiting');
  };
  return (
    <div className="flex flex-wrap items-center gap-2 min-h-8" role="status" aria-live="polite" data-testid="refresh-status">
      {(['quota', 'tasks', 'history'] as const).map(branch => (
        <span key={branch} data-testid={`refresh-${branch}`} className={`chip-like text-xs ${status[branch].phase === 'failed' ? 'text-status-warn' : 'text-secondary'}`}>
          {t(`dashboard.refresh.${branch}`)}: {message(status[branch])}
        </span>
      ))}
      {status.summary_write_failed ? <span className="text-xs text-status-warn">{t('dashboard.refresh.summaryFailed')}</span> : null}
    </div>
  );
}
