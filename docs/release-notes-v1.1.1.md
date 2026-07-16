# codexU v1.1.1

这是一次 Codex token 统计准确性补丁。

## 修复内容

- 修复长会话或并发任务中 Codex token 明细被成倍放大的问题。
- 优先使用 `token_count.info.last_token_usage` 记录的单次真实增量，不再依赖可能短暂回退的累计快照猜测本次用量。
- 兼容只有 `total_token_usage` 的旧日志；累计字段出现负修正时只保留非负增量，不会把整个会话累计值重新加入。
- 升级 Codex 本机统计缓存版本，安装 v1.1.1 后会自动重建此前受影响的缓存。
- 新增累计快照回退单元测试和完整 Codex parser fixture，防止同类问题再次出现。

## 根因

Codex 的累计 `total_token_usage` 在长会话和并发任务中可能出现小幅回退。旧解析器只要发现任一累计字段下降，就把当前累计值当作一个全新的计数周期，导致数亿 token 被重复加入。该问题来自上游 v1.0.5 已有的累计差分逻辑，不是 OpenClaw、Claude Code 或 Hermes 的重复归属造成的。

codexU 显示的是本机 session 事件统计；Codex App 显示服务端汇总。服务端日桶可能延迟更新，且时区和额度权重口径不同，两者不保证实时完全一致。

## 安装包

- Apple Silicon: `codexU-1.1.1-mac-arm64.dmg`
  - SHA-256: `5e59a3471ef81316f48fa610e503a047bdb6ec2bcce75db120e570147b03743d`
- Intel: `codexU-1.1.1-mac-x86_64.dmg`
  - SHA-256: `b6476fb48cbdd5cf978921016f3f2843d49914570ccb03c8bdd2540d0d4c144e`

安装包使用 ad-hoc 签名，未执行 Apple notarization。首次打开时请按 README 的“隐私与安全”说明手动允许。
