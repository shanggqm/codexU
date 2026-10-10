import { useCallback, useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { CodexDashboardSnapshot, DashboardView } from '../types/models';
import { isTauriRuntimeAvailable, requireTauriRuntime } from '../utils/tauri';
import { getVisualTestData } from '../types/visualTest';

export function useUsage() {
  const [dashboard, setDashboard] = useState<CodexDashboardSnapshot | null | undefined>(undefined);
  const [status, setStatus] = useState<DashboardView['refresh'] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const revision = useRef(-1);
  const mounted = useRef(false);
  const load = useCallback(async (command = 'get_local_usage') => {
    try {
      requireTauriRuntime();
      const view = await invoke<DashboardView>(command);
      if (!mounted.current || view.revision < revision.current) return;
      revision.current = view.revision;
      setDashboard(view.dashboard); setStatus(view.refresh);
      setLoading([view.refresh.quota, view.refresh.tasks, view.refresh.history].some(s => s.phase === 'loading'));
      setError(null);
    } catch (e) {
      if (mounted.current) { setError(String(e)); setLoading(false); }
    }
  }, []);
  useEffect(() => {
    mounted.current = true;
    const visualDashboard = getVisualTestData()?.dashboard;
    if (visualDashboard) {
      setDashboard(visualDashboard); setLoading(false);
      return () => { mounted.current = false; };
    }
    let cancelled = false;
    let unlisten: (() => void) | undefined;
    const subscribe = async () => {
      if (isTauriRuntimeAvailable()) {
        try {
          const dispose = await listen('usage:updated', () => { void load('get_usage_state'); });
          if (cancelled) { dispose(); return; }
          unlisten = dispose;
        } catch (e) { if (!cancelled) setError(String(e)); }
      }
      if (!cancelled) await load();
    };
    void subscribe();
    // Backend owns the configured TTL; this read never forces an extra cycle.
    const interval = window.setInterval(() => { void load(); }, 10_000);
    return () => { cancelled = true; mounted.current = false; unlisten?.(); window.clearInterval(interval); };
  }, [load]);
  return { dashboard, status, loading, error, refresh: () => load('refresh_usage') };
}
