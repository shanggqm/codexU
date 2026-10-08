# codexU v1.3.2

codexU v1.3.2 修复 ChatGPT 升级后的 macOS 额度读取，并改善历史统计的增量加载、缓存回收和完整结果保留。

## 主要更新

- 兼容新版 ChatGPT 的内嵌 Codex CLI 布局，继续支持旧版应用、改名或移动的应用及常规 CLI 安装路径。
- macOS 首页先恢复本地摘要，额度、任务和完整历史分别刷新；历史统计使用可恢复的 SQLite 增量索引与每日归档。
- 修复过期中间报告积压造成的缓存空间耗尽，分批回收可复用页面，保留当前发布结果、使用中的版本和原始日志。
- 历史补全期间继续显示上次完整累计与领导力；缓存不足、索引占用和读取失败时提供明确状态，成功后自动恢复。
- 优化趋势日期计算，补充历史去重、追加/改写、检查点恢复、缓存和首页回归测试，并纳入发布门禁。
- 同步提供 Windows x86_64 MSI/NSIS 安装包；本次历史索引与 ChatGPT 路径修复属于 macOS 实现。

## 验证

- 发布前全局内存风险门禁：PASS；已复核进程/管道退出、定时器和观察者清理、读取/缓存上限及父路径终止边界。
- macOS 双架构发布包装：PASS；`make release-package` 完成回归测试、DMG checksum/挂载、Mach-O 架构和严格签名验证。
- Windows runner 的 Rust format/test、Web 构建及 MSI/NSIS 打包：PASS；79 项测试通过，1 项需要本机已登录 Codex CLI 的测试按既有条件跳过。[构建记录](https://github.com/shanggqm/codexU/actions/runs/37762489774)，Windows 源码与最终发布版本一致，打包版本显式设为 1.3.2。
- 跨平台四个安装包与四个 checksum 汇总：PASS；`make release-cross-platform-check` 验证全部 SHA-256，并修复该校验脚本缺少可执行权限的问题。
- 本机升级与原生窗口复核：PASS；从已验证的 Apple Silicon DMG 安装至 `/Applications/codexU.app`，版本 1.3.2 / build 29；首页摘要、官方额度、任务和完整累计均正常显示。

## 安装包

- 版本：1.3.2，内部构建号：29。
- Apple Silicon：`codexU-1.3.2-mac-arm64.dmg`
- Intel：`codexU-1.3.2-mac-x86_64.dmg`
- Windows MSI：`codexU-1.3.2-windows-x86_64.msi`
- Windows NSIS：`codexU-1.3.2-windows-x86_64-setup.exe`

## SHA-256

```text
9d38d1a50ec3f3bf838023ae49b737174e368224947301f8c90439c2eff5dbe3  codexU-1.3.2-mac-arm64.dmg
4e13f90378d9fccea0ae4713e0c19936861ab7a62fd77e0f46dead086428c3ee  codexU-1.3.2-mac-x86_64.dmg
4dc541ee0f47eaf100fdaa20fea7ab964893b34524ce4c886f4e9b2d1dda370e  codexU-1.3.2-windows-x86_64.msi
c0333b05010ccf1e9529ae09d2893044887fc6e4086b1c801150a19afec012e9  codexU-1.3.2-windows-x86_64-setup.exe
```

## 签名与支持边界

macOS 应用使用仓库默认的 ad-hoc 签名，发布包装已验证签名与架构；未执行 Apple notarization（未 notarize）。Windows 安装包未代码签名。本轮不声称完成 Windows 原生视觉矩阵、Intel 实机运行或所有 macOS 版本的原生性能验收。
