# codexU v1.0.4

本次 patch 版本重点修复菜单栏空闲高 CPU 与耗电问题，并降低后台轮询和长期缓存的资源成本。

## 主要更新

- 修复菜单栏状态项外观监听与图像更新之间的重绘反馈回环，避免空闲时持续占用 CPU。
- 缓存 Runtime 模板图像，避免每次状态栏重绘都重新读取和解码 PNG。
- 主窗口或菜单栏状态弹窗可见时，任务看板保持 10 秒刷新；完全后台时降为 60 秒，并允许系统合并定时器唤醒。
- Codex session 用量内存缓存和持久缓存限制为 1024 条，优先保留最近更新的会话。
- 全局快捷键支持在设置中自定义，并增加组合键校验、冲突检测和录制交互。

## 验证

- 修复前的已发布版本在系统 CPU 资源日志中曾达到 68%–82% 的平均 CPU；修复后的本地 30 秒空闲对照约为 0.6%。
- 通过状态栏、统计时区、更新检查、全局快捷键与解析器自测。
- 通过 Apple Silicon 与 Intel 双架构 DMG、checksum、挂载、Mach-O 架构和 codesign 验证。

## 安装包

- Apple Silicon：`codexU-1.0.4-mac-arm64.dmg`
- Intel：`codexU-1.0.4-mac-x86_64.dmg`

## SHA-256

```text
562742240d7907b72d3c8fd45bd0b50a9f401b51813d9a19c8454a5f2f12f20f  codexU-1.0.4-mac-arm64.dmg
52e2e6d7c0dcc7f5ed2445730c53c58c759a4361393d49a3622ae08fe3d91753  codexU-1.0.4-mac-x86_64.dmg
```

本次安装包使用仓库默认签名流程构建，未执行 Apple notarization。
