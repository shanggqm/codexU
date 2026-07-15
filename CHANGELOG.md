# Changelog

## Unreleased

## 1.0.5 - 2026-07-14

- Codex 额度展示会按可信响应中的实际窗口数量自适应：仅有 7 天额度时使用单环、单进度条和居中百分比；双窗口恢复完整双环；服务明确返回零个额度限制时显示无限制状态。
- 对失败、畸形、未知、重复和部分额度响应采用 fail-closed 策略，保留最近一次可信布局并标记为陈旧数据，避免短暂异常误判为无限制或造成界面跳变。
- 恢复完整环形粒子效果并将粒子约束在进度环描边内；默认仅在主窗口可见、置前且聚焦时渲染，省电模式仅在悬停环形区域时渲染，同时响应低电量、温控和减少动态效果状态。
- 进一步收紧后台刷新条件和定时器容差：任务看板只在相关视图活跃时高频刷新，窗口失焦、最小化、被遮挡或位于其他 Space 时停止无效动画和刷新。
- 优化单额度菜单栏样式、重置倒计时与对比度：百分比居中显示，文字会根据已填充/未填充背景自动切换颜色，重置时间使用 `↻ 5d` 等紧凑语义并补齐 VoiceOver 描述。
- Claude Code transcript 缓存升级为纳秒级文件指纹，兼容迁移旧缓存、清理已删除文件记录并显式报告写入失败，减少不必要的重复解析。
- 扩展发布门禁，新增额度拓扑、状态栏像素布局、粒子生命周期、缓存迁移与热路径回归测试。

## 1.0.4 - 2026-07-13

- 修复 Codex 仅返回 7 天额度窗口时被误标为 5 小时额度的问题；额度窗口现在按 `windowDurationMins` 归一化，不再依赖 `primary` / `secondary` 槽位顺序，并覆盖单窗口、双窗口、顺序颠倒和未知窗口自测。
- 修复菜单栏状态项的外观监听与重绘反馈回环，避免空闲时持续占用单个 CPU 核心，并缓存 Runtime 模板图像以减少解码开销。
- 任务看板改为主窗口或状态弹窗可见时每 10 秒刷新、完全后台时每 60 秒刷新，并为周期任务增加系统可合并的定时器容差。
- 为 Codex session 用量内存缓存和持久缓存增加 1024 条容量限制，优先保留最近更新的会话，避免历史数据长期增长抬高内存基线。
- 全局快捷键支持在设置中自定义，并增加组合键校验、冲突检测与录制交互。

## 1.0.3 - 2026-07-11

- 新增跟随系统、UTC 日界线与固定 IANA 时区三种自然日统计模式，Codex、Claude Code、趋势、任务与 SQLite 回退统一使用同一时区口径。
- 为时区切换增加加载与成功反馈，并缓存最近使用的统计时区快照，频繁往返切换可即时完成。
- 菜单栏、Runtime 卡片和主窗口统一优先使用 session `token_count` 精细今日用量，仅在精细数据缺失时回退 SQLite 粗略统计。
- 修复刷新期间重复点击导致当前结果被丢弃、等待时间翻倍的问题；刷新中按钮会禁用并保留原有 hourglass 状态。
- 统一 K/M/B token 格式化，修复单位边界舍入，并补充时区、DST、格式化和回退口径自测。

## 1.0.2 - 2026-07-10

- 状态栏新增简约、经典、丰富三档展示模式，可独立选择已用量/剩余量口径、5 小时额度、7 天额度、今日 token 与重置倒计时。
- 简约模式使用无 Logo 的加粗蓝紫双环；经典模式使用纯数字额度环；丰富模式保留完整标签、进度条、百分比和重置时间。
- 状态栏背景改为透明，品牌 Logo 派生为系统单色模板，文字与图标按菜单栏实际深浅自动适配。
- 提高 5h/7d 标签和重置时间的对比度，今日总量改用系统菜单栏正文尺寸，并保持固定宽度与稳定布局。
- 设置窗口新增共享渲染器实时预览，所有显示配置即时保存并应用。

## 1.0.1 - 2026-07-10

- 兼容新版 ChatGPT/Codex App 的动态路径，同时保留旧版 App 与标准 CLI 回退。
- 双环额度新增低开销逆时针粒子流，只在剩余额度弧段内运动，并支持“减少动态效果”。
- 关闭主窗口且继续后台运行时，隐藏 Dock 图标并保留菜单栏状态项；从菜单栏或快捷键唤回主窗口时恢复标准窗口模式。

## 1.0.0-beta03 - 2026-07-09

- 新增 GitHub Release 更新检测：默认每天最多自动检查一次，并默认接收 beta/prerelease 版本；发现新版时在主窗口、菜单栏 Runtime 浮窗和设置系统区提示。
- 更新入口提供匹配当前 Mac 架构的 DMG 下载和 GitHub Release 页面跳转；不会静默下载或自动安装。
- 设置窗口将“更新”并入“系统”区，保留自动检查开关，并把手动检查、最新状态和操作按钮合并到一行。
- Runtime 展示配置改为单行多选 segmented 控件，Codex / Claude Code 带 logo，并继续确保至少保留一个 Runtime。
- 新增版本比较、GitHub Release 元数据解析、ETag/24 小时缓存和 `--self-test-updates` 自测入口。

## 1.0.0-beta02 - 2026-07-08

- 新增 Runtime 展示设置：默认展示 Codex 和 Claude Code，可在设置中选择要显示的 Runtime，并确保至少保留一个。
- 用量趋势中的近 7 日折线图和最近半年热力图新增应用内 hover 详情浮窗，展示日期、Runtime、token 总量、可用拆分和统计口径；近 7 日折线图支持整图横向 hover 切换日期，不再要求精确悬停圆点。
- 设置页 checkbox 统一改为 switch 开关，语言/外观分段控件圆角与设计标准对齐，所有设置操作控件右对齐。
- 主窗口标题栏 Runtime 与操作按钮组右对齐，并增加顶部间距，避免贴近窗口边框。
- 将主界面升级为标准 macOS App 窗口，支持 Dock、系统红黄绿窗口控制、最小化，以及关闭主窗口后继续在菜单栏运行。
- 保留菜单栏状态项，并增强 Runtime 浮窗：新增设置入口，支持打开主窗口、打开设置和退出。
- `Command + U` 调整为显示/隐藏主窗口；窗口最小化时会恢复并唤到前台。
- 菜单栏浮窗支持在其他全屏 App 的当前 Space 中展示。
- 新增设置窗口，集中管理语言、外观、主窗口置顶和关闭行为；语言、主题和 PRO 状态不再常驻主窗口顶部。
- 恢复主窗口 Liquid Glass 材质和半透明质感，并优化标题栏工具区、窗口圆角、顶部间距和按钮尺寸。
- 新增 Codex 与 Claude Code 彩色 Runtime 图标资源，统一主窗口、菜单栏浮窗和 Runtime 切换控件的视觉。
- 更新 README 截图、安装说明和源码构建示例。

## 0.4.0 - 2026-07-07

- Added a multi-runtime usage architecture with Codex and Claude Code providers.
- Added Claude Code local transcript parsing for tokens, trends, projects, tool usage, Skill usage, and tasks.
- Added a menu bar runtime popover with Codex and Claude Code summary cards and total tokens today.
- Added a top-level Codex / Claude Code switch in the main widget.
- Added runtime-aware `--dump-json` output with `schemaVersion: 2`, `aggregate`, `runtimes[]`, and legacy Codex compatibility fields.
- Added local statusLine snapshot support for Claude Code active quota, with missing/stale diagnostics.

## 0.3.0 - 2026-07-04

- Reworked the lower dashboard into three tabs: today's task board, usage trend, and project board.
- Added a six-month daily token heatmap with local `token_count` event aggregation, fixed week-by-week matrix layout, percentile-based purple intensity levels, and per-day hover tooltips.
- Added a last-7-day line chart with total, daily average, and previous-period comparison.
- Added project usage rankings for the last 7 days and all time, with thread counts, recent activity, and detailed/approximate source labels.
- Added tool usage TOP10 with call counts, categories, and session-share token/value estimates.
- Added Skill usage TOP20 analytics based on local Skill load events.
- Added local analytics JSON output for trend, project, and tool data in `--dump-json`.
- Added foreground pin mode while keeping `Command + U` as a temporary foreground toggle.
- Fixed heatmap month labels so each month starts on the week column containing that month's first day.
- Documented the v0.3.0 product requirements in `docs/PRD-v0.3.0.md`.

## 0.2.0 - 2026-07-01

- Introduced the new Apple-inspired visual system with refined light and dark palettes, elevated surfaces, consistent control styling, and updated token colors.
- Added system, light, and dark appearance modes with a persistent top-level mode switch.
- Added detailed token parsing from local Codex `token_count` session events, including uncached input, cached input, output, and monthly API-equivalent value estimates.
- Redesigned the value progress card around Plus, Pro100, Pro200, and full monthly quota milestones.
- Simplified the quota area by moving reset times under the dual ring and removing redundant 5-hour and 7-day progress rows.
- Increased the widget height so task board rows have more room to render cleanly.
- Added explicit Intel Mac and Apple Silicon DMG packaging targets and documented x86_64 release artifacts.

## 0.1.4

- Added Chinese and English UI text support.
- Default language now follows the system time zone: Chinese for China/Hong Kong/Macau/Taiwan time zones, English otherwise.
- Added a top bar `中 | EN` language switch that persists the manual selection.

## 0.1.3

- Added the app icon to the widget header.
- Moved account status into a right-side pill next to the plan badge.
- Updated the README screenshot for the new header layout.

## 0.1.2

- Added local desktop widget UI for Codex quota, token usage, trend, and task board.
- Added `Command + U` foreground/desktop layer toggle.
- Added DMG packaging, checksum generation, signing hooks, and notarization helper.
- Added local data source probe command.
