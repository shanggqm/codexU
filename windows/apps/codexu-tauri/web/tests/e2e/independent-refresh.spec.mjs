import { test, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { getRepositoryIdentity } from './support/live-data.mjs';

test('real AppState restart, independent slow/failing branches, recovery and source invalidation', async ({ page }, testInfo) => {
  test.skip(process.env.CODEXU_REFRESH_HARNESS !== '1', 'requires the explicit loopback AppState harness');
  test.setTimeout(120_000);
  const evidence = path.join(testInfo.outputDir, 'refresh-evidence');
  await mkdir(evidence, { recursive: true });
  const observations = [];
  async function observe(name) {
    const view = await page.evaluate(() => window.__TAURI_INTERNALS__.invoke('get_usage_state'));
    const states = await page.getByTestId('refresh-status').innerText();
    observations.push({ name, states, view });
    await page.screenshot({ path: path.join(evidence, name + '.png'), fullPage: true });
  }
  async function scenario(mode) {
    await page.selectOption('#scenario', mode);
    await page.click('#apply-scenario');
  }
  await page.goto('/tests/refresh-harness.html');
  await expect(page.getByTestId('refresh-history')).toContainText('saved summary; details pending');
  await expect(page.getByTestId('refresh-quota')).toContainText('Up to date');
  await expect(page.getByTestId('refresh-tasks')).toContainText('Up to date');
  await expect(page.getByRole('region', { name: 'Local token metrics' })).toContainText('300');
  await expect(page.locator('.leadership-overview-card')).toContainText('67');
  await observe('restart-history-loading');
  await expect(page.getByTestId('refresh-history')).toContainText('Up to date', { timeout: 10_000 });
  for (const branch of ['quota', 'tasks', 'history']) {
    await scenario(branch + '-slow');
    await expect(page.getByTestId('refresh-' + branch)).toContainText('Updating');
    for (const sibling of ['quota', 'tasks', 'history'].filter(s => s !== branch)) await expect(page.getByTestId('refresh-' + sibling)).toContainText('Up to date');
    await observe(branch + '-slow');
    await expect(page.getByTestId('refresh-' + branch)).toContainText('Up to date', { timeout: 10_000 });
    await scenario(branch + '-fail');
    await expect(page.getByTestId('refresh-' + branch)).toContainText('Refresh failed');
    for (const sibling of ['quota', 'tasks', 'history'].filter(s => s !== branch)) await expect(page.getByTestId('refresh-' + sibling)).toContainText('Up to date');
    await expect(page.getByRole('region', { name: 'Local token metrics' })).toContainText('300');
    await observe(branch + '-failed');
    await scenario('recover');
    await expect(page.getByTestId('refresh-' + branch)).toContainText('Up to date');
  }
  await page.click('#language');
  await expect(page.getByTestId('refresh-history')).toHaveText('历史: 已更新');
  await scenario('history-fail');
  await expect(page.getByTestId('refresh-history')).toContainText('刷新失败 · 显示上次数据');
  await observe('chinese-history-failed');
  await scenario('recover');
  await expect(page.getByTestId('refresh-history')).toHaveText('历史: 已更新');
  await scenario('cold');
  await expect(page.getByTestId('refresh-history')).toContainText('正在读取');
  const metrics = page.getByRole('region', { name: '本地 Token 指标' });
  await expect(metrics).toContainText('--');
  await expect(metrics).not.toContainText('300');
  await observe('cold-history-missing');
  await expect(page.getByTestId('refresh-history')).toHaveText('历史: 已更新', { timeout: 10_000 });
  await scenario('source');
  await expect(page.getByRole('region', { name: '本地 Token 指标' })).toContainText('50');
  await observe('new-source-complete');
  await writeFile(path.join(evidence, 'observations.json'), JSON.stringify({ identity: await getRepositoryIdentity(), transport: 'loopback HTTP IPC adapter', account: 'synthetic, no authentication', observations }, null, 2) + '\n');
});
