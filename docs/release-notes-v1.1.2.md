# codexU v1.1.2

本版本把 Codex App 官方用量与本机明细同时放到界面中，解决“数据已经读取但没有显示”的口径问题。

## 主要变化

- Codex 仪表盘顶部直接显示 `account/usage/read` 返回的 Codex App 官方累计 token。
- 官方数据明确标记为“Codex App 官方累计 / 服务端汇总”。
- 原有三张用量卡改名为“本机今日 / 本机近 7 天 / 本机累计”，不再与官方口径混淆。
- 本机 session 事件继续提供缓存输入、未缓存输入、输出、趋势、项目归因和 API 等效价值。
- `--dump-json` 的 schema-v2 Runtime 快照和兼容 Codex 快照新增 `cloudLifetimeTokens`，可以直接核验官方数值。

## 原因

codexU 之前已经调用 Codex App 的 `account/usage/read` 并解析 `summary.lifetimeTokens`，但该字段只保存在内存快照中，没有进入首页或 JSON 输出。界面因此只显示本机 session 统计，与 Codex App 的服务端累计存在明显差异。

v1.1.2 不再把两套数据混成一个数字：官方累计用于和 Codex App 对照；本机统计用于官方接口没有提供的精细分析。服务端日桶可能延迟更新，所以本机与官方数值仍可能不同，但来源和用途现在清楚可见。

## 安装包

- Apple Silicon: `codexU-1.1.2-mac-arm64.dmg`
  - SHA-256: `9fe9189fd479d60cc6fd41df2592cc6fef2776d0eb9783de3bbcdf943abe8e00`
- Intel: `codexU-1.1.2-mac-x86_64.dmg`
  - SHA-256: `23c04628389c6d333e6933ed6aaf5ed1c1f5984bebb3808bc5aafcbcd9c6995c`

安装包使用 ad-hoc 签名，未执行 Apple notarization。首次打开时请按 README 的“隐私与安全”说明手动允许。
