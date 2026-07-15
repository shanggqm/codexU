# codexU v1.0.4

本次 patch 版本重点修复菜单栏空闲高 CPU 与耗电问题、Codex 单独返回 7 天额度窗口时被误标为 5 小时额度的问题，并降低后台轮询和长期缓存的资源成本。

## 主要更新

- 修复菜单栏状态项外观监听与图像更新之间的重绘反馈回环，避免空闲时持续占用 CPU。
- 缓存 Runtime 模板图像，避免每次状态栏重绘都重新读取和解码 PNG。
- 主窗口或菜单栏状态弹窗可见时，任务看板保持 10 秒刷新；完全后台时降为 60 秒，并允许系统合并定时器唤醒。
- Codex session 用量内存缓存和持久缓存限制为 1024 条，优先保留最近更新的会话。
- 全局快捷键支持在设置中自定义，并增加组合键校验、冲突检测和录制交互。
- Codex 额度窗口改为按 `windowDurationMins` 识别 5 小时与 7 天语义，不再依赖 `primary` / `secondary` 槽位顺序；未知或重复窗口不会被错误标注。

## 验证

- 修复前的已发布版本在系统 CPU 资源日志中曾达到 68%–82% 的平均 CPU；修复后的本地 30 秒空闲对照约为 0.6%。
- 通过额度单窗口/双窗口/顺序颠倒回归测试，以及状态栏、统计时区、更新检查、全局快捷键与解析器自测。
- 通过 Apple Silicon 与 Intel 双架构 DMG、checksum、挂载、Mach-O 架构和 codesign 验证。

## 安装包

- 本次重新打包使用内部构建号 17，用户可见版本仍为 1.0.4。
- Apple Silicon：`codexU-1.0.4-mac-arm64.dmg`
- Intel：`codexU-1.0.4-mac-x86_64.dmg`

## SHA-256

```text
f1a441cd523078b7aea65659df01e4386a870f3688331a81ab4e3a66bd4ffc90  codexU-1.0.4-mac-arm64.dmg
6b8acd3f9d0c7615cb699af18ee58f6aa7e09eef9dde8b8adbe08a2da38aedc9  codexU-1.0.4-mac-x86_64.dmg
```

本次安装包使用仓库默认签名流程构建，未执行 Apple notarization。
