// Only the IPC transport is emulated. The HTTP test process runs real AppState,
// real history/task providers and real summary IO with synthetic local inputs.
const endpoint = 'http://127.0.0.1:14815';
window.isTauri = true;
export async function request(command, args = {}) {
  const response = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ command, args }) });
  if (!response.ok) throw Error(`Harness request failed: ${response.status}`);
  return response.json();
}
const callbacks = new Map();
const listeners = new Map();
let next = 1;
let revision = -1;
const emit = (event, payload) => {
  for (const [id, listener] of listeners) if (listener.event === event) callbacks.get(listener.handler)?.({ event, id, payload });
};
window.__TAURI_INTERNALS__ = {
  metadata: { currentWindow: { label: 'main' }, currentWebview: { label: 'main' } },
  transformCallback(handler) { const id = next++; callbacks.set(id, handler); return id; },
  unregisterCallback(id) { callbacks.delete(id); },
  async invoke(command, args = {}) {
    if (command === 'plugin:event|listen') { const id = next++; listeners.set(id, args); return id; }
    if (command === 'plugin:event|unlisten') { listeners.delete(args.eventId); return; }
    const result = await request(command, args);
    if (command === 'set_settings') emit('settings:changed', result);
    return result;
  },
};
window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener(_event, id) { listeners.delete(id); } };
async function events() {
  try {
    const result = await request('__events', { revision });
    if (result.revision !== revision) { revision = result.revision; emit('usage:updated', revision); }
  } catch (error) { document.getElementById('control-state').textContent = String(error); }
  window.setTimeout(events, 50);
}
void events();
document.getElementById('apply-scenario').onclick = async () => {
  const mode = document.getElementById('scenario').value;
  document.getElementById('control-state').textContent = '正在应用…';
  await request('__scenario', { mode });
  if (mode === 'restart' || mode === 'cold') { window.location.reload(); return; }
  await request('refresh_usage');
  document.getElementById('control-state').textContent = '场景已应用';
};
document.getElementById('language').onclick = async () => {
  const settings = await request('get_settings');
  await window.__TAURI_INTERNALS__.invoke('set_settings', { req: { language: settings.language === 'en' ? 'zh-Hans' : 'en' } });
};
await import('/src/main.tsx');
