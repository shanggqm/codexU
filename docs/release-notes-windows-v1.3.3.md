# codexU Windows v1.3.3

codexU Windows v1.3.3 补齐历史增量索引、首页摘要恢复与独立刷新，并修复读取失败覆盖完整统计的问题。

## 主要更新

- Windows 历史读取失败时保留同来源的完整累计与 AI 领导力，显示失败状态；解锁后无需再次修改日志即可重新读取。
- 可恢复 SQLite 增量索引与每日归档，正确处理追加、截断、原子替换、累计计数器、会话去重及统计时区；缓存预算与分批回收不删除原始日志。
- 启动先恢复有界摘要，官方额度、任务与历史分别更新；没有历史数据时不伪造 0，切换来源后拒绝迟到的旧响应。
- 包含单实例、再次启动唤回与托盘恢复修复，使用 stable MSVC 工具链，并保留后台 app-server 不弹 CMD 的行为。
- 本次仅更新 Windows x86_64 MSI/NSIS。macOS 继续下载 [v1.3.2](https://github.com/shanggqm/codexU/releases/tag/v1.3.2)，本次没有 macOS 安装包。
- Windows 安装包未代码签名，首次运行可能显示安全提示。

## 构建与验证

- 产品源码：上游 PR #53 合并提交 `c5fd6f42ca53a02df059728084fcfc953399afaa`；打包通过显式 Tauri config override 设置版本 1.3.3，与本次 tracked Windows config 相同。发布元数据提交仅调整版本、文档和校验入口，不改变产品逻辑。
- Windows-only 构建：[GitHub runner](https://github.com/shanggqm/codexU/actions/runs/38073772711)，`platform=windows`。构建成功；Rust 109 项测试通过、3 项既定 ignored，Web 构建及 MSI/NSIS 打包通过。
- `make release-windows-check`：PASS；MSI ProductVersion 1.3.3 / x64、NSIS ProductVersion 1.3.3、manifest 与两份 SHA-256 一致；两个安装包均为 NotSigned。
- 全局内存风险门禁已执行，并复核风险清单；macOS 源码及资源与 v1.3.2 完全一致。Windows 历史解析/索引、摘要的字节与事实预算及刷新生命周期继承已验收实现。
- 未在本次发布安装或启动真实 Tauri 窗口；不访问认证账户，不声称新完成 Windows 10、DPI 或本机升级验收。
- 任意日志内部改写与增长同时发生时，使用文档中的 `--verify-history-index` 全扫描核验，不将有界增量指纹冒称任意改写检测。

## 安装包与 SHA-256

```text
e59e9df4e8d9f5adbd487daf20906176ef99dc1262a98a447eb74a30fe6440de  codexU-1.3.3-windows-x86_64.msi
c4fdd845ea6bbbda3c622f8c727a36d7555790aa9441631e6918e31cded8e399  codexU-1.3.3-windows-x86_64-setup.exe
```

## 发布边界

- Tag：`windows-v1.3.3`，发布名称：`codexU Windows v1.3.3`，稳定版，上传两个安装包和两个 checksum。
- 独立 Windows tag 避免触发 `v*` 双平台打包；Release 使用 `--latest=false`，保持通用 Latest 为带有 macOS 安装包的 v1.3.2。README 的 Windows 链接直接指向本次发布。
- macOS Info.plist 的版本 1.3.2 / build 29 与已有 DMG、tag、Release 资产保持原样；本次不进行 Apple 签名或 notarization。
