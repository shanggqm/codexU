# codexU v0.3.0 产品需求文档

版本：V1.0<br>
日期：2026-07-04<br>
作者：Codex<br>
状态：Draft

## 1. 需求概述

### 1.1 背景

codexU v0.2.0 已经能展示 Codex 额度窗口、今日/近 7 日/累计 token、token 拆分、API 等效价值和今日任务看板。当前问题是：界面仍偏向“当前状态展示”，缺少对使用模式的解释能力。用户可以看到“用了多少”，但较难回答以下问题：

- 最近一段时间 Codex 使用是否稳定，是否集中在少数高峰日？
- 本月订阅价值回收进度背后的每日趋势是什么？
- 哪些项目最消耗 token？
- 哪些工具调用最频繁，工具使用是否解释了 token 增长？
- 今日任务、用量趋势、项目分析之间如何在有限桌面空间内清晰切换？

v0.3.0 的目标是把 codexU 从“额度与任务小组件”升级为“Codex 使用分析小组件”，在不暴露敏感内容的前提下，让用户快速理解自己的 Codex 使用结构。

### 1.2 产品目标

- 在桌面小组件内提供三类高频视角：今日任务、用量趋势、项目看板。
- 让用户能在 10 秒内判断：今天忙不忙、最近用量是否异常、哪个项目消耗最多。
- 用稳定、可解释的聚合指标替代 prompt 原文、tool arguments 等敏感内容披露。
- 保持当前本地读取、不上传数据的隐私边界。
- v0.3.0 控制范围，不引入日志健康、Goal、多 agent 图谱等次级分析面板。

### 1.3 用户角色与场景

| 角色 | 场景 | 期望 |
| --- | --- | --- |
| 高频 Codex 用户 | 每天多项目并行使用 Codex | 快速知道今天哪些任务还在进行、哪些项目最耗用额度 |
| 订阅型用户 | 希望判断 Plus/Pro 订阅是否值得 | 看到每日趋势、近 7 日变化和项目/工具结构 |
| 工具型开发者 | 经常使用 shell、patch、browser、MCP 等工具 | 了解工具调用结构，判断耗时/耗 token 的工作类型 |
| 隐私敏感用户 | 不希望桌面小组件暴露 prompt 或文件内容 | 只展示聚合指标、脱敏路径和本地口径说明 |

### 1.4 范围

In Scope：

- 将“今日任务看板”改为 tab 容器中的默认 tab。
- 新增“用量趋势”tab，包含半年每日用量热力图、模型活动概览，以及带近 7 日摘要的 Codex 专用模型用量面积图。
- 用量热力图默认展示最近半年，并保持固定周矩阵，必要时删减边缘日期以保证矩阵完整。
- 新增“项目看板”tab，包含项目用量排行、工具使用 TOP10；工具 token 估算作为 P1 增强能力，可降级。
- 增加必要的数据口径说明、tooltip、空状态、降级策略。
- 复用本地 SQLite、session JSONL、已有 token parser 与缓存策略。

Out of Scope：

- 不展示 prompt 原文、tool arguments、附件内容、auth 信息。
- 不新增日志健康面板、Goal 面板、多 agent 子线程图谱。
- 不做云同步、用户登录、远程数据上传。
- 不在用量趋势 tab 底部展示本月累计、估算价值和预计月底卡片。
- 不做精确官方账单口径，所有 API 等效价值仍标注为本地估算。

## 2. 信息披露原则

### 2.1 用户价值分级

| 等级 | 信息类型 | 用户价值 | 展示策略 |
| --- | --- | --- | --- |
| P0 | 额度剩余、今日任务、半年热力图、模型活动概览、模型总量趋势、项目排行、工具调用次数 | 直接影响用户是否继续发起 Codex 工作 | 主界面或 tab 首屏直接展示 |
| P1 | 工具 token 估算、成本估算、项目估算价值 | 帮助用户理解使用结构和订阅价值 | tab 内展示，配 tooltip |
| P2 | 推理档位、归档占比、CLI 版本、动态工具配置 | 排查和复盘有价值，但日常不一定需要 | v0.4 或详情页候选 |
| P3 | prompt、tool arguments、附件正文、auth、raw logs | 敏感或噪声高 | 不展示 |

### 2.2 文案原则

- 面向结果，而不是面向数据表字段。例如使用“最近 7 日”而不是“sevenDayTokens”。
- 对估算口径显式标注“估算”，避免让用户误认为是官方账单。
- 对不完整数据使用“本地记录不足”而不是“无数据”，减少误导。
- 项目路径默认只展示最后一级目录，完整路径仅在 hover tooltip 中展示。
- 工具 token 用量使用“估算 token”，不使用“消耗 token”。

### 2.3 隐私原则

- 默认不展示用户消息、assistant 回复、tool 输入参数、附件正文。
- tooltip 也不展示敏感正文，只展示日期、项目名、路径尾名、token、调用次数、估算金额。
- 完整 cwd 路径可在 tooltip 展示，但应作为可配置项；默认可只展示路径尾名。
- 所有数据均来自本机 `~/.codex`，PRD 与 UI 文案需要继续强调“不上传”。

## 3. 信息架构

### 3.1 顶层布局

当前主界面保留顶部 header、额度环、token 指标和羊毛进度。下方“今日任务看板”区域升级为 tab 区域。

Tab 顺序：

1. 今日任务
2. 用量趋势
3. 项目看板

默认 tab：今日任务。

Tab 文案：

| Tab | 中文文案 | 英文文案 | 说明 |
| --- | --- | --- | --- |
| 今日任务 | 今日任务 | Today | 当前活跃、待处理、定时、完成任务 |
| 用量趋势 | 用量趋势 | Usage | 每日 token 热力图和近 7 日摘要 |
| 项目看板 | 项目看板 | Projects | 项目排行和工具使用分析 |

### 3.2 Tab 切换行为

- 使用 segmented control 或轻量 tab bar。
- tab 状态仅保存在当前进程内即可；v0.3.0 不要求持久化。
- 手动刷新应刷新所有 tab 数据，但 UI 仍停留在当前 tab。
- 自动刷新时：
  - 任务看板保持当前 10 秒刷新节奏。
  - 用量趋势、项目看板跟随 5 分钟完整刷新。

## 4. 功能需求

### F1. 今日任务 Tab

优先级：P0

用户故事：

作为高频 Codex 用户，我希望默认看到今日任务状态，以便快速知道当前有哪些线程正在推进、哪些任务已经完成。

功能说明：

- 保留当前四列：进行中、待处理、定时、完成。
- 作为 tab 容器默认内容。
- 保持当前每列最多展示 3 条，超出显示 `+ N 项`。
- 保留任务标题、相对更新时间、项目名、token 简写、状态 chip。

字段设计：

| 字段 | 来源 | 展示文案 | 备注 |
| --- | --- | --- | --- |
| title | `threads.title` / `preview` | 任务标题 | 为空时显示 `Untitled` / `未命名` |
| updatedAt | `recency_at` / `updated_at` / `archived_at` | `刚刚`、`12 分钟前` | 当前逻辑可复用 |
| cwd | `threads.cwd` | 路径尾名 | tooltip 可展示完整路径 |
| tokens | `threads.tokens_used` | `1.2M` | 简写即可 |
| automation schedule | `automation.toml` 或 `codex-dev.db.automations` | `每天 09:00` | v0.3.0 建议优先读 DB，TOML 作为回退 |

验收标准：

- [ ] 打开应用默认显示今日任务 tab。
- [ ] 当前任务看板视觉和信息不出现功能回退。
- [ ] tab 切换后任务看板仍按 10 秒节奏刷新。
- [ ] 无 SQLite 数据时显示明确空状态。

### F2. 用量趋势 Tab：半年每日热力图

优先级：P0

用户故事：

作为订阅型 Codex 用户，我希望看到最近半年每天的使用强度，以便判断自己的使用是否连续、是否集中在少数高峰日，以及订阅价值是否被充分利用。

功能说明：

- 默认展示最近半年每日用量热力图。
- 每个格代表一天。
- 按周排列，视觉参考 GitHub contribution graph。
- 月份显示在顶部，星期一到星期日标签显示在左侧。
- 热力图保持固定周矩阵，最右侧为包含最新日期的当前周。
- 色阶使用灰色到紫色主色调，不使用全绿色。
- hover 每日格子显示 tooltip。

热力图文案：

| 元素 | 中文 | 英文 |
| --- | --- | --- |
| 标题 | 最近半年用量 | Last 6 months |
| 图例低值 | 少 | Less |
| 图例高值 | 多 | More |
| 空值 tooltip | `{date} 无本地 token 记录` | `No local token records on {date}` |
| 有值 tooltip | `{date} · {tokens} tokens · 估算 {usd}` | `{date} · {tokens} tokens · est. {usd}` |

tooltip 字段：

| 字段 | 来源 | 说明 |
| --- | --- | --- |
| date | token event timestamp 本地日期 | 使用系统时区 |
| totalTokens | session JSONL `token_count` delta | 优先使用精细 token 事件 |
| inputTokens | `input_tokens` delta | 可选展示 |
| cachedInputTokens | `cached_input_tokens` delta | 可选展示 |
| outputTokens | `output_tokens` delta | 可选展示 |
| reasoningOutputTokens | `reasoning_output_tokens` delta | 可选展示 |
| estimatedCostUSD | 按现有价格模型估算 | 标注估算 |

色阶规则：

- 0：中性灰。
- 1-4 档：紫色由浅到深。
- 阈值建议使用最近半年非零日用量的分位数：P25、P50、P75、P90。
- 当非零天数少于 5 天时，降级为线性分档。
- 避免直接按最大值线性映射，防止单日峰值压扁其他天的视觉差异。

数据口径：

- 优先：解析 `~/.codex/sessions/**/rollout-*.jsonl` 和 `~/.codex/archived_sessions/*.jsonl` 中 `token_count` 的正向 delta。
- 回退：使用 `threads.updated_at` + `threads.tokens_used` 进行粗略日归因。
- 当使用回退口径时，标题旁显示 `粗略统计` / `Approx.`。

验收标准：

- [ ] 默认覆盖最近半年，包含今天。
- [ ] 每个日期最多一个格子，hover 可看到具体 token。
- [ ] 热力图始终是固定周矩阵，七行分别代表周一到周日。
- [ ] 零用量日期和无记录日期视觉可区分度不过高，避免误导。
- [ ] 色阶图例和实际分档一致。
- [ ] 窗口宽度 820px 下不横向溢出。

### F3. 用量趋势 Tab：模型活动概览

优先级：P0

用户故事：

作为 Codex 用户，我希望在热力图旁边看到当前日期范围内的模型活动摘要，以便快速判断主要使用模型和活动覆盖，而不需要逐格读取。

功能说明：

- 展示所选日期范围内的用量最高模型。
- 展示活跃日期数和活跃模型数。
- 展示按所选日期范围计算的日均用量。
- 范围与模型用量趋势面积图同步，默认最近 30 天，可选 60/90/180 天。

字段设计：

| 字段 | 中文文案 | 英文文案 | 价值 |
| --- | --- | --- | --- |
| topModel | 用量最高模型 | Top model | 判断主要使用模型 |
| activeDayCount | 活跃日期 | Active days | 判断使用连续性 |
| activeModelCount | 活跃模型 | Active models | 判断模型覆盖范围 |
| rangeDailyAverageTokens | 范围日均 | Range daily avg | 判断选定范围的平均强度 |

推荐文案：

- `用量最高模型 gpt-5.6`
- `活跃日期 18 / 30`
- `活跃模型 6`
- `范围日均 1.8M`

业务规则：

- 精细模型归因优先读取同一 session 中、位于 `token_count` 事件之前最近的 `turn_context.model`；每次 `turn_context` 都更新当前归因，若其中没有模型字段则清空上一轮模型并回退到 `threads.model`。
- 当趋势整体使用线程时间回退口径时，模型曲线也按线程模型归因，并继续标注 `粗略统计` / `Approx.`。

验收标准：

- [ ] 概览指标与面积图所选日期范围同源。
- [ ] 只有当前范围内有 token 的模型参与活跃模型统计。
- [ ] 范围日均按选定日期数计算，不把无记录日期从分母中删除。
- [ ] 指标文案在中英文下不溢出。

### F3.1. 用量趋势 Tab：模型时间序列面积图

优先级：P0（仅 Codex runtime）

功能说明：

- 在热力图和模型活动概览卡片下方新增全宽模型趋势卡片，默认展示最近 30 天，并允许切换最近 60、90、180 天；热力图仍保持最近半年。
- 采用非堆叠叠加面积图：每个模型使用独立颜色的半透明面积和折线，共享同一纵轴。
- 叠加一条中性颜色虚线表示全局每日总用量；卡片摘要同步显示近 7 日总量、日均和较前 7 日变化。
- 默认按所选日期范围内的 token 总量显示 Top 8 模型；其余模型按日期合并为“其他模型”。模型不足 9 个时不生成聚合序列。
- 纵轴在 `Token` 与 `估算费用（USD）` 之间切换；费用属于 API 等效估算，不代表官方账单。模型没有独立价格时按 GPT-5.5 价格作参考折算，并在控件文案和 tooltip 中明确标注为参考费用。
- 精细 token 事件可显示费用；粗略线程口径没有输入/缓存/输出拆分，费用控件禁用并解释原因。
- 面板只在 Codex runtime 显示模型活动概览和模型序列；Claude Code 的 `modelTrends` 为 `nil`，表示当前不支持模型归因，并保留原有近 7 日摘要，而非显示为 0 个模型。

验收标准：

- [ ] 所有序列共享所选范围的完整日期轴（默认 30 天，可选 60/90/180 天），空闲日期填充为 0，未来日期不绘制。
- [ ] Top 8 排序按所选范围 token 总量、范围内最近 7 日 token、模型 ID 稳定排序；剩余模型逐日求和正确。
- [ ] 图例、描边、tooltip 同时显示模型名称，颜色不是唯一信息通道。
- [ ] 总用量虚线与每日全局用量一致，tooltip 将总用量列为首行。
- [ ] Token/费用切换不改变序列和日期；粗略口径不显示伪造费用 0。
- [ ] 近 7 日总量、日均和较前 7 日变化随 Token/费用口径同步计算。
- [ ] 无模型记录、单模型、超过 8 个模型、浅色/深色和中英文状态均可读且不溢出。

### F4. 用量趋势 Tab：本月预测与价值解释

优先级：Out of Scope

用户故事：

作为订阅型用户，我希望知道当前月度节奏是否可能覆盖订阅成本，以便判断自己是否需要调整使用方式或订阅档位。

功能说明：

- v0.3.0 不在用量趋势 tab 底部展示本月累计、本月估算和预计月底卡片。
- 主界面已有“羊毛进度”，用量趋势 tab 优先保持热力图和模型总量趋势的聚焦表达。

字段设计：

无。

文案说明：

无。

验收标准：

- [ ] 用量趋势 tab 不显示本月累计、本月估算、预计月底卡片。

### F5. 项目看板 Tab：项目用量排行

优先级：P0

用户故事：

作为多项目 Codex 用户，我希望看到哪些项目消耗了最多 token，以便理解使用成本来源，并决定优先优化哪个项目的工作流。

功能说明：

- 展示项目用量排行。
- 支持两个口径：所有项目、最近 7 天。
- 默认展示最近 7 天。
- 每行展示项目名、token、估算价值、线程数、最近活跃时间。
- 项目名默认使用 cwd 最后一段。

筛选文案：

| 选项 | 中文 | 英文 |
| --- | --- | --- |
| 最近 7 天 | 近 7 天 | 7 days |
| 所有项目 | 全部 | All time |

字段设计：

| 字段 | 来源 | 展示文案 | 说明 |
| --- | --- | --- | --- |
| projectName | `cwd.lastPathComponent` | 项目名 | 空路径显示 `未归类` |
| fullPath | `threads.cwd` | tooltip | 默认不直接展示 |
| tokens | `threads.tokens_used` 或 session delta | `12.4M` | 近 7 日优先用 session delta |
| estimatedCostUSD | token split + model price | `$12.34` | 估算 |
| threadCount | `COUNT(*)` | `8 线程` | 可解释项目活跃度 |
| lastActiveAt | `MAX(recency_at/updated_at)` | `2 小时前` | 排查旧项目霸榜 |

业务规则：

- 最近 7 天口径优先使用 session JSONL 事件按日期聚合，再通过 SQLite `rollout_path -> cwd` 归因到项目。
- 当 session 事件缺失时，回退到 `threads.updated_at >= dayStart-6` 的线程级 tokens。
- 所有项目口径可使用 `threads.tokens_used` 聚合，性能更稳。
- 默认不显示完整路径；tooltip 显示完整路径。

验收标准：

- [ ] 最近 7 天和全部口径可切换。
- [ ] 默认按 token 降序排列。
- [ ] 至少展示 TOP 8，空间不足时展示 TOP 5。
- [ ] 项目名过长时截断，tooltip 保留完整路径。
- [ ] 回退口径有 `粗略统计` 标记。

### F6. 项目看板 Tab：工具使用 TOP10

优先级：P0

用户故事：

作为工具型开发者，我希望看到 Codex 主要调用了哪些工具，以便理解自己的使用模式，比如偏 shell、代码编辑、浏览器验证还是资料检索。

功能说明：

- 展示工具调用 TOP10。
- 支持调用次数和估算 token。
- 工具 token 需要明确标注为“估算”。
- 默认按调用次数排序。

字段设计：

| 字段 | 来源 | 展示文案 | 说明 |
| --- | --- | --- | --- |
| toolName | session JSONL `function_call.payload.name` / `custom_tool_call.payload.name` | 工具名 | 如 `exec_command`、`apply_patch` |
| callCount | 事件计数 | `1,234 次` | 稳定准确 |
| estimatedTokens | turn-level token delta | `估算 2.3M` | 归因估算 |
| share | `estimatedTokens / total` | `18%` | 可选 |
| failedCount | output/status 异常或 aborted turn | `3 失败` | P1，可后续增强 |

工具分类建议：

| 分类 | 工具示例 | 展示名建议 |
| --- | --- | --- |
| Terminal | `exec_command`、`write_stdin`、`shell_command` | 终端 |
| Edit | `apply_patch` | 代码编辑 |
| Browser/Web | `web_search_call`、`click`、`new_page`、`take_snapshot` | 浏览/检索 |
| Image | `image_generation_call`、`view_image` | 图片 |
| Docs/MCP | `query_docs`、`resolve_library_id`、MCP tools | 文档/MCP |
| Planning | `update_plan`、`create_goal`、`update_goal` | 计划 |

工具 token 归因规则：

- 稳定准确：调用次数。
- 估算 token：
  - 以 turn 为单位，计算该 turn 内 `token_count` 的正向 delta。
  - 如果 turn 内出现多个工具，按调用次数均分该 turn delta。
  - 如果无法识别 turn，则只展示调用次数，不展示 token。
- UI 文案必须使用 `估算 token` / `Est. tokens`。

验收标准：

- [ ] TOP10 至少显示工具名和调用次数。
- [ ] 工具 token 无法估算时不显示错误数值，显示 `--`。
- [ ] tooltip 说明 token 归因为估算。
- [ ] 不展示工具参数内容。

### F7. 数据口径说明与空状态

优先级：P0

用户故事：

作为用户，我希望知道这些统计来自哪里、是否完整，以便正确理解数据，而不是把本地估算当作官方账单或官方额度。

功能说明：

- 在用量趋势和项目看板标题旁增加小型 info affordance。
- hover 或点击显示口径说明。
- 数据缺失时给出可行动空状态。

口径说明文案：

中文：

> 使用本机 Codex session token_count 事件估算；缺失时回退到本机线程更新时间统计。API 等效价值为估算，不代表官方账单。

英文：

> Estimated from local Codex session token_count events. Falls back to thread updated_at when detailed events are unavailable. API-equivalent value is an estimate, not an official bill.

空状态文案：

| 场景 | 中文 | 英文 |
| --- | --- | --- |
| 没有 session JSONL | 未找到精细 token 事件，已使用线程更新时间粗略统计。 | Detailed token events were not found. Using thread update times as an approximation. |
| 没有任何本地数据 | 暂无本机 Codex 使用记录。完成一次 Codex 会话后再刷新。 | No local Codex usage records yet. Run one Codex session and refresh. |
| 没有项目路径 | 暂无可归类项目。 | No project paths available. |
| 工具事件缺失 | 暂无工具调用记录。 | No tool call records available. |

验收标准：

- [ ] 每个估算指标都有口径提示。
- [ ] 所有空状态不使用技术错误堆栈。
- [ ] 数据缺失时界面仍可用。

## 5. 数据需求

### 5.1 核心数据源

| 数据源 | 用途 | 当前状态 |
| --- | --- | --- |
| `~/.codex/state_5.sqlite.threads` | 项目、线程、cwd、model、tokens、recency | 已使用；`model` 作为精细记录缺失时的回退 |
| `~/.codex/sessions/**/rollout-*.jsonl` | 精细 token、工具调用、模型曲线、热力图 | 已解析 `token_count` 和 `turn_context.model` |
| `~/.codex/archived_sessions/*.jsonl` | 历史 session | 已用于 token，需纳入趋势 |
| `~/.codex/sqlite/codex-dev.db.automations` | automation 下一次/上一次运行 | 新增优先读取 |
| `~/.codex/automations/**/automation.toml` | automation 回退 | 当前已使用 |

### 5.2 新增数据模型建议

#### UsageDayBucket

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | String | `yyyy-MM-dd` |
| date | Date | 本地日期 |
| tokens | Int64 | 总 token |
| inputTokens | Int64 | 输入 token |
| cachedInputTokens | Int64 | 缓存输入 token |
| outputTokens | Int64 | 输出 token |
| reasoningOutputTokens | Int64 | 推理输出 token |
| estimatedCostUSD | Double | API 等效估算 |
| sourceQuality | Enum | `detailed` / `approximate` |

#### ModelUsageTrend

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | String | 规范化后的本机模型标识；无记录时为单独占位标识 |
| model | String? | JSONL `turn_context.model`，缺失时使用线程 `model` |
| dayBuckets | `[UsageDayBucket]` | 最近半年按天聚合的该模型 token |
| summary | `UsageTrendSummary` | 该模型最近 7 日、日均和与前 7 日对比 |
| activeDayCount | Int | 该模型有记录的日期数 |

`UsageTrend.modelTrends` 为可选字段：`nil` 表示当前 Runtime 不支持模型归因；空数组表示支持归因，但当前范围没有可归因的模型记录。

#### ModelUsageAreaSeries

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | String | 模型 ID 或 `other-models` |
| model | String? | 展示用模型名；聚合序列为空 |
| isAggregate | Bool | 是否为“其他模型”聚合序列 |
| dayBuckets | `[UsageDayBucket]` | UI 按所选范围派生的日期点；调试 JSON 保留最多半年 |
| activeDayCount | Int | 有 token 记录的日期数 |
| sourceQuality | Enum | `detailed` / `approximate` |
| costAvailable | Bool | 粗略线程口径时为 `false` |
| usesReferencePricing | Bool | 模型无独立价格、按 GPT-5.5 参考价折算时为 `true` |

#### ProjectUsage

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | String | cwd hash 或 cwd |
| name | String | 路径尾名 |
| fullPath | String | 完整 cwd |
| tokens | Int64 | token |
| estimatedCostUSD | Double? | 估算价值 |
| threadCount | Int | 线程数 |
| lastActiveAt | Date? | 最近活跃 |
| sourceQuality | Enum | `detailed` / `approximate` |

#### ToolUsage

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | String | 工具名 |
| name | String | 工具名 |
| category | String | 分类 |
| callCount | Int | 调用次数 |
| estimatedTokens | Int64? | 估算 token |
| estimatedCostUSD | Double? | 估算价值 |
| failedCount | Int? | 失败次数，P1 |

### 5.3 性能要求

- 半年热力图不应每 10 秒全量扫描 JSONL。
- 复用现有 `SessionUsageCacheEntry` 思路，按文件路径、size、mtime 缓存解析结果。
- 用量趋势和项目看板完整刷新周期建议为 5 分钟。
- 任务看板仍保持 10 秒轻量刷新。
- 初次解析耗时超过 2 秒时，UI 应先展示 loading 状态，不阻塞窗口启动。

## 6. 交互与视觉要求

### 6.1 Tab 容器

- 放置在当前任务看板 section 的标题区域下方或替代标题右侧。
- 使用 macOS segmented control 风格。
- icon 可选：
  - 今日任务：`checklist`
  - 用量趋势：`calendar`
  - 项目看板：`folder`

### 6.2 热力图

- 每个日格建议 10-12px，间距 3-4px。
- 圆角不超过 3px。
- 色阶：
  - 0：`surfaceTrack`
  - 1：浅紫
  - 2：中浅紫
  - 3：主紫
  - 4：深紫
- 不使用大面积渐变背景。
- 月份标签紧凑显示，避免挤压格子。

### 6.3 项目排行

- 使用紧凑列表，不使用大卡片堆叠。
- 每行建议包含：
  - 左：项目名 + 最近活跃
  - 中：细进度条
  - 右：tokens + 估算价值
- TOP 行可用主色强调，但避免全页单色。

### 6.4 工具 TOP10

- 使用水平条形排行。
- 工具名过长时截断。
- 工具分类可用小图标，不需要长文解释。
- tooltip 展示分类、调用次数、估算 token 和口径。

## 7. 非功能性需求

### 7.1 隐私

- 不上传任何数据。
- 不展示 prompt、tool arguments、附件正文、auth token。
- 完整路径是否展示在 tooltip 需后续确认，默认建议只展示路径尾名。

### 7.2 可用性

- 数据缺失时展示可理解的空状态。
- 中英文文案都要避免按钮或指标溢出。
- 小组件默认高度不应显著超过 v0.2.0；tab 内容在当前区域内切换。

### 7.3 准确性

- 明确区分精细统计和粗略统计。
- 工具 token 归因为估算，不能与官方账单等同。
- 项目最近 7 日口径优先使用 session 事件，不能简单用全量线程 token 冒充最近 7 日。

### 7.4 可维护性

- 将数据读取聚合逻辑与 SwiftUI View 解耦。
- 新增类型命名应围绕业务语义：`UsageDayBucket`、`ModelUsageTrend`、`ModelUsageAreaSeries`、`ProjectUsage`、`ToolUsage`。
- 尽量复用现有价格估算逻辑和 token parser。

## 8. v0.3.0 建议优先级

P0 必做：

- Tab 容器与默认今日任务 tab。
- 最近半年每日用量热力图。
- 模型活动概览。
- Codex 模型用量面积图：Top 8 + 其他模型、总用量虚线、Token/估算费用切换。
- 项目用量排行：最近 7 天 / 全部。
- 工具使用 TOP10：调用次数。
- 数据口径说明与空状态。

P1 推荐：

- 工具估算 token。
- 项目估算价值。
- automation 使用 `codex-dev.db` 补充下一次/上一次运行。

P2 延后：

- 工具失败次数。
- 推理档位分析。
- Goal 面板。
- 日志健康面板。
- 多 agent 子线程图谱。

## 9. 开放问题

| 编号 | 问题 | 影响范围 | 建议 |
| --- | --- | --- | --- |
| Q1 | 完整 cwd 是否允许在 tooltip 展示？ | 隐私与可用性 | 默认不展示完整路径，提供设置项或仅调试模式展示 |
| Q2 | 工具 token 估算是否进入 v0.3.0 P0？ | 实现复杂度 | v0.3.0 至少展示调用次数，token 估算作为 P1 |
| Q3 | 热力图色阶按分位数还是固定阈值？ | 视觉稳定性 | 默认分位数，非零天数不足时线性降级 |
| Q4 | 项目最近 7 日是否必须精确到 session event？ | 准确性 | 优先精细口径，缺失时明确标记粗略统计 |
| Q5 | tab 状态是否需要持久化？ | 用户习惯 | v0.3.0 不持久化，后续根据反馈决定 |

## 10. 验收总表

- [ ] 默认进入今日任务 tab。
- [ ] 三个 tab 在中英文下均可正常显示。
- [ ] 用量趋势 tab 显示最近半年热力图，hover 有每日 token tooltip。
- [ ] 模型用量趋势摘要包含近 7 日总量、日均和较前 7 日变化。
- [ ] 项目看板支持最近 7 天和全部项目切换。
- [ ] 项目排行展示 token、线程数、最近活跃时间。
- [ ] 工具 TOP10 展示调用次数，估算 token 不可用时降级为 `--`。
- [ ] 所有估算项都有“估算”文案或 tooltip。
- [ ] 不展示 prompt、tool arguments、附件正文、auth token。
- [ ] 初次加载和刷新不阻塞主窗口。

## 11. 变更记录

| 日期 | 版本 | 说明 | 作者 |
| --- | --- | --- | --- |
| 2026-07-04 | V1.0 | 创建 v0.3.0 PRD 初稿 | Codex |
