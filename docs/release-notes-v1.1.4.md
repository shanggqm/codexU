# codexU v1.1.4

本版本把 Codex 官方 Token 统计的指标和中文单位与 ChatGPT 个人资料对齐。

## 主要变化

- 官方累计 Token 数直接使用 Codex App `account/usage/read` 返回的 `lifetimeTokens`。
- 官方峰值 Token 数直接使用同一接口返回的 `peakDailyTokens`，并与官方每日桶最大值交叉验证。
- 中文官方数值按与个人资料一致的“亿”显示，不再把 `29.6亿` 粗略显示成 `3.0B`。
- 官方区域依次展示累计、峰值、最近一天和近 7 天；四项均来自同一服务端数据源。
- JSON 诊断新增 `cloudPeakDailyTokens` 和 `cloudUsageTrend.peakBucket`，方便精确核验。
- 本机原始上下文仍保持独立的非官方用量口径，不参与官方累计或峰值计算。

## 验证样本

- 累计：`2,964,716,296` → `29.6亿`
- 峰值：`1,240,624,629` → `12.4亿`
- 最近一天：`313,597,618` → `3.1亿`
- 近 7 天：`2,710,251,622` → `27.1亿`

## 安装包

- Apple Silicon: `codexU-1.1.4-mac-arm64.dmg`
  - SHA-256: `cf32751cec0939251eb4e8414393cd7680439e40eaade47fa0f337199c75f807`
- Intel: `codexU-1.1.4-mac-x86_64.dmg`
  - SHA-256: `48a2888a2e662839340bf044d98ae68a82696d649b54788793ad20977ec9c5cb`

安装包使用 ad-hoc 签名，未执行 Apple notarization。首次打开时请按 README 的“隐私与安全”说明手动允许。
