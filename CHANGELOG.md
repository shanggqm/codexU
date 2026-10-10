# Changelog

## 1.3.2 - 2026-10-08

- 修复 ChatGPT 升级后内嵌 Codex CLI 路径变更导致额度和任务读取失败的问题，兼容新旧应用布局及常规 CLI 安装。
- macOS 首页优先恢复有界摘要，额度、任务和历史分别刷新；历史统计改为本地 SQLite 增量索引和可恢复的每日归档。
- 修复过期中间报告积压导致历史缓存达到空间上限的问题，改为有界分批回收，保留已发布和使用中的结果及原始日志。
- 历史缺失或失败时保留上次完整累计与领导力，显示缓存空间不足、索引占用等明确状态；避免部分归档覆盖完整统计。
- 优化趋势日期计算，并扩展历史解析、去重、恢复、缓存和首页回归，纳入发布包装与内存风险门禁。
- 同步提供 Windows x86_64 MSI/NSIS 安装包；历史增量索引及本次 ChatGPT 路径修复属于 macOS 实现。

## Unreleased

## 1.3.1 - 2026-09-01

- 完成独立 Windows x86_64 Tauri Dashboard V0：Overview、Tasks、AI Leadership、Usage、Inference、Projects、Skills 和 Settings 八个 Web surface 统一接入本地数据管线。
- Windows app-server 子进程启动使用 `CREATE_NO_WINDOW`，首次打开或点击 Refresh 时不再弹出 CMD/命令行窗口，同时保留额度读取、loopback 请求和子进程清理行为。
- Windows 版本继续保持本地优先和隐私边界，只读取本机 Codex transcript、SQLite 与 automation 元数据；不上传 usage、线程、路径、日志或账户数据。
- 推理性能聚合补齐本地统计时区、DST 边界、有界流式读取、指纹缓存和共享刷新索引；缺失或非法事件不伪造成有效样本。
- 固化 Windows glass surface、Playwright 合同/fixture、native exact-HWND 采集边界、shell lifecycle 检查和 MSI/NSIS 发布脚本校验。

## 1.3.0 - 2026-08-04

- 新增本机推理性能监测：从最近 28 天 Codex rollout 识别完整模型调用，按模型与推理强度展示平均耗时、P50、P90、有效吞吐和 reasoning token 占比，并支持今日、7 日均和 28 日均视图。
- 推理性能样本经过时间戳噪声过滤、有界去重和本地持久化；不保存或展示 prompt、回复、路径，也不把指标冒充 TTFT 或可见文本解码 TPS。
- 推理性能监测使用独立的历史存储和聚合路径，不改变现有额度、token、趋势与任务数据口径。
- 发布流程补齐 macOS 双架构 DMG 与 Windows x86_64 MSI/NSIS 安装包的 CI 构建、checksum 和跨平台资产校验。
- 保持本地优先和隐私边界：不新增遥测，不上传 usage、线程、路径、日志或账户数据。

## 1.2.1 - 2026-07-24

- 修复 AI 领导力尚未形成等级、但今日已有 Agent 记录时，指挥半径 Canvas 因零轨道参与节点布局而触发 `SIGTRAP` 连续崩溃的问题；零轨道状态现在会跳过节点绘制，并补充对应回归测试。
- Codex 用量趋势新增模型活动概览与按模型面积图，支持 30、60、90、180 天范围、Top 8 + 其他模型、token / API 等效估算费用切换和全局总量虚线。
- 模型费用缺少专属价格时明确标注使用 GPT-5.5 参考价格，优化图例、行样式和 tooltip 的信息层级；Claude Code 暂不支持模型归因时保留清晰降级说明。
- 继续保持本地优先：模型归因、领导力修复和趋势聚合均在本机完成，不新增遥测或用户数据上传。

## 1.2.0 - 2026-07-22

- 全网首推本地 AI 领导力评估模型：合并 Codex 与 Claude Code 的 Worker 证据，以滚动 28 天的管理半径、劳动力杠杆、编排能力和自主运行生成 0–100 分与七级中文称号。
- 主界面新增动态“等级徽章 + 指挥半径”第一视觉，展示 28 天领导 Agent、AI 工时和峰值并发；轨道节点按今日 Agent 数刷新、最多 12 个，并在窗口聚焦时公转与呼吸。
- 新增 AI 领导力详情 Tab：等级进度、四项核心指标、四维分值、每日 AI 工时/Agent/峰值组合趋势和项目贡献；个人得分始终合并全部 Runtime。
- AI 领导力只使用事实或可推导的本机结构证据，不让成本、交付和估算区间进入分数；缺失数据不伪造成 0。
- 七级称号更新为“碳基牛马、赛博监工、分身队长、硅基领主、硅基统帅、超级个体、人类最强者”，并配套高分辨率 PNG 徽章。
- 七级称号补齐正式英文映射；等级进度 Title 改用语义前景色，在浅色与深色模式下均保持可读。
- 修复 AI 领导力 SQLite 查询的无界进程输出读取：增加 32 MiB 总量上限、POSIX 分块读取、stderr 重定向和超限进程清理；AI 领导力与 Claude transcript 磁盘缓存补齐读写字节上限。
- 发布流程新增 GitHub Release 精简正文生成与校验，只公开版本摘要和主要更新，完整验证与 checksum 继续保留在仓库发布说明中。

## 1.1.5 - 2026-07-21

- 修复从已有 Codex 对话创建分支后，分支继承的 `token_count` 历史被再次计入累计、今日和近 7 日用量的问题。
- 通过父子线程元数据与 token 事件公共前缀识别继承历史，只保留分支创建后的新增用量；SQLite 回退、精细统计、趋势和项目排行统一使用去重口径。
- 分支事件身份使用紧凑指纹，并以有界两遍扫描替代全量 session entry 常驻；全局内存风险门禁新增对应阻断检查。

## 1.1.4 - 2026-07-17

- 修复 app-server 长连接 stdout 使用 Foundation 定长读取时等待凑满 64 KiB、导致初始化响应无法消费和 Codex 额度超时的问题；改用有背压的 POSIX 分块读取，并补充部分响应与 EOF 回归测试。
- 同步修复今日任务 app-server 长连接的读取语义，保留 1 MiB 缓冲上限、单请求并发、超时和进程清理边界。
- 全局内存风险门禁新增 app-server 部分响应检查，发布包装强制执行 pipe 部分读取与 EOF 自测。

## 1.1.3 - 2026-07-17

- 修复 macOS 13 上 Claude Skill 项目路径上溯越过文件系统根目录后持续生成 `/..` 链的问题，避免启动刷新长期占满 CPU 并导致常驻内存无限增长。
- 路径解析增加显式根目录终止和 visited 路径去重双重保护，并补充 macOS 13 Foundation 根目录父路径异常的回归测试。
- 全局内存风险门禁新增父路径上溯终止、循环去重与回归断言检查；发布包装强制运行 Claude Skill 路径自测。

## 1.1.2 - 2026-07-17

- 修复 macOS 13 上 app-server 长连接与一次性额度读取可能无界累积输出、悬挂请求和子进程的问题，增加缓冲区、并发、超时、EOF 与强制清理边界。
- Codex 与 Claude Code 会话解析改为流式读取并限制单行大小；进程输出、Skill 文件、内存/持久缓存和解析工作集增加容量上限与淘汰，降低大型本地数据集下的内存峰值。
- 发布流程新增全局内存泄露风险门禁，扫描生产 Swift 中的无界 FileHandle/Process/Pipe、Timer 生命周期、缓存及观察者清理风险；门禁未通过时禁止打包和发布。
- 新增冷/热缓存、大型本地 Codex 数据集和失效 app-server socket 的内存稳定性验证，不新增遥测或用户数据上传。

## 1.1.1 - 2026-07-16

- 今日任务看板改为来源感知的可信分类：Codex 使用“最近活跃、待继续、定时、今日归档”，Claude Code 保留显式运行、失败、阻塞、完成和未知状态；归档与近期活动不再被包装成成功或实时执行。
- 重排任务卡片信息层级，优先展示标题、工作区、事实时间和状态；支持整卡打开 Codex Session、hover/手型/键盘焦点反馈，并移除无行为图标与弱语义头像。
- Codex automation 支持常见 RRULE、时区和下次运行时间计算；规则不完整时只展示可验证周期，不再把配置更新时间当作运行时间。
- 新增 Codex Team 月额度窗口识别与菜单栏剩余额度表达，兼容月额度字段别名、单/月窗口拓扑和缺失数据降级。
- Claude Code Skill 路径可从个人、项目、嵌套、插件及旧版 command 目录回退定位，并补充静态 Token/字节估算和去重合并。
- 主窗口支持 820–1280pt 宽度调整并恢复上次尺寸；额度重置明细统一支持悬停查看。
- 新增隐私安全的本地性能采样、阶段验收门禁与项目级 Skill 统一目录，扩展任务、额度、性能、Claude Skill 路径和 macOS 兼容性自测。

## 1.1.0 - 2026-07-15

- 新增受控配色插件体系：内置默认、青花瓷、故宫红、千里江山、敦煌飞天和兰亭晨曦六套稳定配色，支持浅色/深色语义 token、受限 SVG 视觉资源、即时预览与切换。
- 新增独立 Liquid Glass 配色图库；社区配色采用仓库内审核投稿机制，提供贡献模板、严格文件白名单、来源与许可证元数据、生命周期控制以及 CI 渲染验证，不开放用户侧自由安装。
- Codex 返回可用额度重置次数时，展示总数和最早到期明细；完整过期列表可通过悬停查看，并在 JSON dump 中输出结构化详情。
- 将最低系统要求降至 macOS 13，同时通过条件编译保留新系统上的 Liquid Glass 能力，并补充双架构兼容性检查。
- 修复 Codex `token_count` 累计字段缺失、局部回退或计数器重置时重复计入整份累计值的问题；优先采用单次 `last_token_usage`（包括仅提供单次用量的事件），并在精细统计与 SQLite 线程统计出现极端倍率差异时安全回退。
- 统一设置页与配色图库的玻璃层级、字体、控件栅格和间距，并补充配色包、状态栏渲染、额度重置次数与 Token 归一化自测。

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
