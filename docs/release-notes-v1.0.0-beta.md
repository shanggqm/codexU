# codexU v1.0.0-beta03

这是 codexU 的 beta03 版本，重点补齐已安装用户的 GitHub Release 更新检测，并继续收敛设置窗口的交互密度。已安装 beta02 的用户可以在设置的系统区手动检查更新，也可以等待默认的每日自动检查提示。

## 主要更新

- 新增 GitHub Release 更新检测，默认每天最多自动检查一次，并默认接收 beta/prerelease 版本。
- 发现新版时，主窗口、菜单栏 Runtime 浮窗和设置系统区都会展示更新提示。
- 更新操作提供匹配当前 Mac 架构的 DMG 下载入口和 GitHub Release 页面入口；codexU 不会静默下载或自动安装。
- 设置窗口将更新能力合并到“系统”区，保留自动检查开关，并把手动检查、状态文案和操作按钮整合到同一行。
- Runtime 展示配置改成单行多选 segmented 控件，Codex / Claude Code 带 logo，并继续保证至少选择一个 Runtime。
- 新增版本比较、GitHub Release 元数据解析、ETag/24 小时缓存和 `--self-test-updates` 自测入口。

## 安装包

- Apple Silicon: `codexU-1.0.0-beta03-mac-arm64.dmg`
- Intel: `codexU-1.0.0-beta03-mac-x86_64.dmg`

## 校验

- `make build`
- `build/codexU.app/Contents/MacOS/codexU --self-test-updates`
- `make release-all`
- `git diff --check`

SHA-256:

```text
d9ea9f7061c7f7a8dd2ef137ba1ae67f63664b9727a21cbb50812fd0003c0ca3  codexU-1.0.0-beta03-mac-arm64.dmg
ddab00f96b0efd7f43a67d547d421843f8000b306298fa7a7fa52244d085291b  codexU-1.0.0-beta03-mac-x86_64.dmg
```
