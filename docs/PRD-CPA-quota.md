# CLI Proxy API 账号额度支持

## 背景

部分用户并不直接使用本机 Codex 账户发起请求，而是把 Codex 指向远端 CLI Proxy API（CPA）账号池。此时本机 `codex app-server` 返回的账户额度不能代表实际可用的远端账号池，需要一个明确启用、可审计的 CPA 额度源。

## 目标

- 用户可以在设置页主动启用或停用 CPA 额度源。
- 用户可以配置 CPA 根地址和 Management API 管理 Key。
- codexU 展示 CPA 中每个启用 Codex 账号的官方 5 小时、7 天和月额度。
- 菜单栏和主额度环提供稳定、可解释的账号池健康信号。
- CPA 配置不改变本机 token、趋势、项目、Skill 和任务的统计口径。

## 非目标

- 不统计 CPA 请求量、模型调用量或费用。
- 不管理、上传、删除或修改 CPA 账号凭据。
- 不展示或保存 CPA 中的 access token、refresh token、原始认证文件或完整邮箱。
- 不把多个账号的百分比或重置时间合并为虚假的统一额度。

## 数据源与接口

功能遵循 CPA Management API：

1. 使用管理 Key 请求 `GET /v0/management/auth-files`。
2. 筛选启用中的 `codex` 账号并读取其不透明 `auth_index`。
3. 对每个账号请求 `POST /v0/management/api-call`，由 CPA 使用该账号访问 `https://chatgpt.com/backend-api/wham/usage`。
4. 按窗口实际时长识别 5 小时、7 天和月额度；月窗口兼容 28–31 天时长，也读取 `additional_rate_limits` 中的月额度。缺失或无法解释的字段不伪造成 0。

Management API 参考：[CLIProxyAPI Management API](https://help.router-for.me/management/api)。

## 展示口径

- 主额度环和菜单栏选择“最低额度账号”：比较每个可用账号的 5 小时、7 天和月额度最低剩余比例，取最小者作为账号池信号。
- 月额度是唯一窗口时，主环和菜单栏使用 `30d` 标签显示；7d + 月额度可以组成双环。若同一账号同时返回 5h、7d 和月额度，主环优先保持 5h/7d 双环，月额度保留在账号卡片中。
- 该口径用于保守提示账号池风险，不代表账号池总容量。
- 主窗口通过横向账号卡片展示全部账号的独立 5h、7d、月额度百分比、重置时间、计划和可用状态。
- 部分账号失败时继续展示成功账号，并明确失败账号数量；全部失败时显示不可用，不显示 0%。
- 刷新失败时沿用上一次成功额度并标记为过期快照，避免布局和数值突然消失。

## 配置与安全

- 默认关闭 CPA，不发起任何 CPA 请求。
- 远程 CPA 必须使用 HTTPS；HTTP 仅允许 loopback 地址。
- 管理 Key 只保存在 macOS Keychain，不进入 `UserDefaults`、日志或 JSON dump。
- CPA 返回的邮箱在进入共享快照前脱敏；界面和 JSON dump 不持有完整邮箱。
- 请求 CPA 时不发送本机 usage、线程、路径、prompt、回复、tool arguments 或 raw logs。
- 配置变化经过短暂防抖后刷新，避免用户输入过程中连续发起请求。

## 错误状态

- 地址或管理 Key 缺失：设置页直接说明，不发起请求。
- 远程 HTTP：拒绝并要求 HTTPS。
- 401/403：说明管理 Key 无效或远程管理未开放。
- 超时、网络失败、无法识别的响应：显示可理解的状态，并保留上次成功快照。
- CPA 没有启用中的 Codex 账号：显示“未返回可用的 Codex 账号”，不回退成 0。

## 验收标准

- 设置页可以启用 CPA、填写 URL 和安全保存管理 Key。
- 本地 CPA Management API 模拟测试覆盖账号枚举、鉴权头、`api-call` 和多账号代表选择。
- 主窗口能显示全部账号卡片，主环和菜单栏使用最低额度账号。
- `--dump-json` 只输出脱敏账号名和聚合额度，不输出管理 Key、完整邮箱、auth token 或原始响应。
- CPA 关闭时保持现有本机 Codex 额度读取行为。
