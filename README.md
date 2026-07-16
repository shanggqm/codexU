# codexU

> [!IMPORTANT]
> **本机多 Agent 定制版。** Codex 始终保留，可在设置中单选 OpenClaw、Claude Code 或 Hermes 作为第二 Agent。各 Agent 的 token 按实际执行方分别统计，任务明确标记来源；未选中的 Agent 不会扫描其本机目录。自动上游更新已关闭，避免覆盖本机定制。

[English](README.en.md)

## 来源与致谢

本项目是 [shanggqm/codexU](https://github.com/shanggqm/codexU) `v1.0.5` 的本机定制分支，遵循原项目 MIT License，并保留原作者 Guomeiqing 的版权与署名。感谢原作者开放源码，让 Codex 额度、用量统计和 macOS 原生界面能够继续扩展。

OpenClaw 集成基于 [openclaw/openclaw](https://github.com/openclaw/openclaw) 的本机数据格式和品牌资源；Hermes 集成基于 Nous Research 的 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 默认 profile 会话库和官方 Logo，两者均采用 MIT License。感谢这些开源项目和社区提供可验证、可扩展的本机 Agent 基础。Claude Code 支持与图标资源继承自上游 codexU；Claude Code 是 Anthropic 产品。本项目与 OpenAI、Anthropic、OpenClaw 或 Nous Research 均无隶属或背书关系。完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

codexU 是一个 macOS 菜单栏与桌面应用，用来查看 Codex 额度、Codex 与所选本机 Agent 各自的 token 用量和统一任务状态。

## 界面截图

![codexU v1.1.0 Codex 与 OpenClaw 主界面](docs/screenshot-v1.1.0-main-openclaw.png)

![codexU v1.1.0 第二 Agent 单选设置](docs/screenshot-v1.1.0-agent-settings.png)

![codexU v1.1.0 菜单栏 Runtime 状态](docs/screenshot-v1.1.0-runtime-menu.png)

## v1.1.2 Codex App 官方统计

v1.1.2 将 Codex App `account/usage/read` 返回的官方累计 token 直接显示在 Codex 仪表盘顶部。此前 codexU 已读取该字段，但没有把它用于界面，因此用户只能看到本机 session 统计，容易误以为两者应当完全一致。

官方累计明确标记为“Codex App 官方累计 / 服务端汇总”；原来的三张卡改名为“本机今日 / 本机近 7 天 / 本机累计”。本机事件仍负责缓存命中、输入/输出拆分、趋势、项目归因和 API 等效价值，因为 Codex App 官方汇总不提供这些明细，并且日桶可能晚于本机事件更新。

![codexU v1.1.2 Codex App 官方累计与本机明细](docs/screenshot-v1.1.2-codex-official.png)

## v1.1.1 统计修复

v1.1.1 修复了 Codex 长会话或并发任务中 token 明细被重复放大的问题。根因是 Codex 的累计 `total_token_usage` 快照可能出现小幅回退，旧算法把任何回退都当作计数器重新开始，从而把整段累计值再次加入。现在优先累计每个事件明确提供的 `last_token_usage`；旧格式缺少该字段时，累计差分中的负修正也不会再触发整段重加。升级后会自动丢弃受影响的旧统计缓存并重新解析本机会话。

codexU 的今日、近 7 天和累计 token 是按本机 session 事件统计；Codex App 的用量页来自服务端汇总，可能存在同步延迟、时区和额度权重差异，因此两者不保证在同一时刻完全一致。

## 适合谁

- 经常使用 OpenAI Codex、Codex CLI 或 Codex 桌面应用的开发者。
- 同时使用 Codex 与 OpenClaw、Claude Code 或 Hermes，希望在一个入口查看本机用量的人。
- 需要快速查看 5 小时/7 天额度、token 用量和重置时间的 ChatGPT Pro / Team 用户。
- 想在桌面查看 Codex 使用状态、减少反复打开浏览器或终端的人。

## 功能

- 展示 Codex 5 小时和 7 天额度的剩余比例、已用比例和重置时间；按协议返回的实际窗口时长识别额度类型，并根据可信响应自适应单环/双环、单进度条/双进度条布局。
- 状态栏 Runtime 菜单展示 Codex 与所选第二 Agent 的卡片、今日 token 与总 token；Codex 卡片额外展示 5 小时和 7 日额度。
- 状态栏支持简约、经典、丰富三档透明显示：简约保留加粗额度环，经典在独立进度环内显示额度数字，丰富展示完整标签、进度条和重置时间；只有一个有效额度窗口时会自动收敛为单额度布局。
- 环形额度保留完整粒子效果；默认只在主窗口可见、置前且聚焦时渲染，省电模式只在鼠标悬停额度环时渲染，后台、低电量、温控或“减少动态效果”状态下自动停用。
- 状态栏额度可切换“已用量 / 剩余量”口径，并可选择显示 5 小时、7 天、今日 token 和重置倒计时；5h/7d 进度色与主界面蓝紫双环一致。
- 状态栏用进度方向区分口径：已用为顺时针/左到右，剩余为逆时针/右到左，不额外占用文字空间。
- 状态栏 Runtime 使用从原始 Logo 精确派生的单色模板，文字与图标按菜单栏实际深浅自动切换黑白；彩色品牌图标继续用于主窗口和浮窗。
- 今日总 token 在状态栏中只显示垂直居中的总量数字，不增加 `T` 标签。
- 今日总量使用系统菜单栏正文尺寸；5h/7d 标签与重置时间使用更易读、仍弱于主数值的动态辅助前景色。
- 设置中固定保留 Codex，并在 OpenClaw / Claude Code / Hermes 中单选一个第二 Agent；切换后主界面、菜单栏和聚合统计同步更新。
- 未选中的第二 Agent 不读取目录、不进入聚合；如果选中的 Agent 尚未安装或没有记录，界面如实显示“暂不可用”，不会偷偷切换到其他 Agent。
- 支持 OpenClaw main-agent transcript、Claude Code 本机会话与 Hermes 默认 profile `state.db` 的 token、趋势、项目、工具和任务统计。
- Codex 即使由 OpenClaw 或 Hermes 调用，token 仍计入 Codex；明确属于 Codex 的记录不会重复计入第二 Agent。
- 任务卡显示 Codex / OpenClaw / Claude Code / Hermes 来源标签，点击后保持打开详情；有效 Codex 线程可从详情页直接在 Codex 中打开。
- 主界面展示本机 CPU 总占用、物理内存占用和温度/热状态；没有公开可用的温度传感器时显示 macOS 热状态，不伪造温度数值。
- 汇总今日、近 7 天和累计 token 用量，并细分未缓存输入、命中缓存输入和输出。
- 按 OpenAI API token 价格估算本月 API 等效价值，并在 Plus、Pro 100、Pro 200 和满额月价值之间展示进度刻度。
- 下方仪表盘支持今日任务、用量趋势、项目排行和 Skill 使用视图。
- 从本机 Codex 线程和启用中的 automations 生成今日任务看板，按进行中、待处理、定时、完成四类组织任务。
- 展示最近半年的每日 token 热力图、最近 7 日趋势摘要和同周期变化。
- 展示最近 7 天与全部项目排行，包含 token、估算价值、线程数和最近活跃时间。
- 展示工具调用 TOP 列表和 Skill 使用 TOP 列表，帮助判断本地 Codex 工作结构。
- 以标准 macOS 窗口运行，支持 Dock、系统窗口控制、最小化和关闭主窗口后继续后台运行；关闭主窗口会隐藏 Dock 图标并保留菜单栏图标。
- 默认使用 `Command + U` 显示或隐藏主窗口，并可在设置中自定义；菜单栏 Runtime 菜单也可以快速打开主窗口、设置或退出。
- 设置窗口支持第二 Agent 单选、中文/英文界面、自动/浅色/深色外观、状态栏内容与实时预览、主窗口置顶、关闭行为、系统状态和更新检查配置。
- 本定制版关闭自动 GitHub Release 检查，仍保留手动检查入口。
- 本地读取数据，不上传 usage、线程或账户数据到第三方服务。

## 羊毛进度

“羊毛进度”是 codexU 对本月 Codex 使用量的 API 等效价值估算。它把本机解析到的未缓存输入、命中缓存输入和输出 token，按对应模型的 OpenAI API token 单价折算成美元金额，并和 Plus、Pro 100、Pro 200 以及满额月价值做对比。这个指标解决的问题是：Codex 额度本身通常只显示百分比和重置时间，token 数量也不容易直观看出“用了多少价值”；羊毛进度提供一个统一的金额口径，帮助你判断本月订阅成本大致回收到了哪个区间。

单次 token 用量的估算公式为：

```text
API 等效价值 =
  未缓存输入 tokens / 1,000,000 * 模型未缓存输入单价
+ 缓存输入 tokens / 1,000,000 * 模型缓存输入单价
+ 输出 tokens / 1,000,000 * 模型输出单价
```

其中 `未缓存输入 tokens = 输入 tokens - 缓存输入 tokens`，缓存输入按不超过输入 tokens 的数量计入。本月羊毛进度会累计当月所有本机 session 的 API 等效价值。进度条的满额终点使用 `2 亿 tokens/天 * 30 天` 估算，并按 30% 未缓存输入、50% 缓存输入、20% 输出的参考 token mix 折算；当前参考价约为 `$7.75 / 1M tokens`，满额月价值约 `$46,500`。进度条采用分段非线性刻度：Plus / Pro 节点保留在前段，超过 Pro 200 后用对数比例映射到满额终点，因此条宽用于扫视阶段进展，不等同于线性美元占比。该金额只是基于 API 价格的等效估算，不代表实际账单或官方返现金额。

## 快捷键和操作

- `Command + U`：默认用于显示或隐藏主窗口，可在设置中自定义；如果窗口已最小化，会恢复并唤到前台。
- 自定义组合至少需要两个修饰键，并包含 Command 或 Control；已知的高风险系统快捷键和辅助功能快捷键不可使用。
- 录制快捷键时按退格键可清空、按 Esc 可取消；之后可恢复默认值或重新录制。
- 应用会检测其他应用的独占快捷键注册冲突；macOS 不提供非独占注册的完整查询能力，如仍与其他应用冲突，请改用其他组合。
- 菜单栏仪表图标：点击后打开 Runtime 菜单；点击 Codex 或所选 Agent 卡片会打开主界面并切到对应 Runtime。
- 菜单栏 Runtime 菜单：展示 Codex 与所选 Agent 的快速状态，并提供打开主窗口、打开设置和退出。
- 设置窗口：选择 OpenClaw / Claude Code / Hermes，配置语言、外观、状态栏展示模式/额度口径/可见指标、主窗口置顶及关闭行为，并可在系统区手动检查 GitHub Release。
- 主窗口顶部刷新按钮：立即刷新额度、token 统计、趋势图和任务看板。
- 系统红黄绿窗口按钮：关闭、最小化或缩放主窗口；关闭后可通过菜单栏图标或快捷键唤回，退出请使用菜单栏 Runtime 菜单或 App 菜单。

## 首次安装：隐私与安全

codexU 目前通过 GitHub Release 的 DMG 安装包分发，不经过 Mac App Store。第一次打开时，macOS 可能会拦截，需要手动允许：

1. 打开 `codexU.app` 一次。如果系统提示无法打开，先取消弹窗。
2. 打开 **系统设置 > 隐私与安全性**。
3. 在 **安全性** 区域找到 `codexU.app`，点击 **仍要打开**。
4. 使用 Touch ID 或密码确认，然后点击 **打开**。

也可以在 Finder 中右键点击 `codexU.app`，选择 **打开**，再确认系统安全提示。

codexU 始终读取本机 `~/.codex/`；只读取当前选中 Agent 对应的 `~/.openclaw/`、`~/.claude/` 或 `~/.hermes/state.db` 结构化用量与任务元数据。本定制版不读取 NAS OpenClaw。

## 安装

从 GitHub Release 下载与你的 Mac 芯片匹配的安装包：

- Apple Silicon：`codexU-<version>-mac-arm64.dmg`
- Intel：`codexU-<version>-mac-x86_64.dmg`

1. 打开 DMG。
2. 将 `codexU.app` 拖到 `Applications` 文件夹。
3. 从 `Applications` 打开 codexU。
4. 按上面的 **首次安装：隐私与安全** 步骤完成手动放行。

安装后不会自动检查或覆盖本机定制版；如有需要，可在设置中手动检查上游版本。

## 运行要求

- macOS 14 或更新版本。
- 本机已安装 Codex。
- 已登录 Codex 账户，额度信息才会显示。
- Codex 至少使用过一次，以便生成 `~/.codex/state_5.sqlite`。
- 第二 Agent 为可选：OpenClaw 使用 `~/.openclaw/agents/main/sessions/*.jsonl`，Claude Code 使用 `~/.claude/projects/**/*.jsonl`，Hermes 使用默认 profile 的 `~/.hermes/state.db`。
- 从源码构建时需要 Xcode Command Line Tools。

## 从源码构建

```sh
make build
```

运行：

```sh
make run
```

安装到 `/Applications`：

```sh
make install
```

检查本机数据源输出：

```sh
make probe
```

## 打包 DMG

```sh
make release
```

`make release` 会按当前构建机器的架构输出安装包。也可以显式打包指定架构：

```sh
make release-arm64
make release-intel
make release-all
```

产物会写入 `dist/`，例如：

```text
dist/codexU-1.1.2-mac-arm64.dmg
dist/codexU-1.1.2-mac-arm64.dmg.sha256
dist/codexU-1.1.2-mac-x86_64.dmg
dist/codexU-1.1.2-mac-x86_64.dmg.sha256
```

Developer ID 签名和 Apple notarization 流程见 [DISTRIBUTION.md](DISTRIBUTION.md)。

## 数据来源

- 账户与额度：`codex app-server` 的 `account/read`、`account/rateLimits/read`、`account/usage/read`。
- Codex token 总量：`~/.codex/state_5.sqlite`，另合并 `~/.openclaw/agents/codex/agent/codex-home/state_5.sqlite` 中 OpenClaw 调用 Codex 产生的用量。
- 精细 token 拆分：`~/.codex/sessions/**/rollout-*.jsonl` 和 `~/.codex/archived_sessions/*.jsonl` 中的 `token_count` 事件。
- 今日任务看板：本机 SQLite 中未归档和今日归档的 Codex 线程。
- 用量趋势和项目排行：本机 session `token_count` 事件聚合；缺失精细事件时回退到线程更新时间的粗略口径。
- 工具和 Skill 使用：本机 session 事件中的工具调用与 Skill 加载记录。
- 定时任务：`~/.codex/automations/**/automation.toml` 中启用的 automation 元数据。
- OpenClaw token：`~/.openclaw/agents/main/sessions/*.jsonl` 中 assistant message 的 `message.usage`；明确标记为 Codex provider/model 的记录会排除，不扫描 NAS 和 OpenClaw 的 Codex 子代理目录。
- OpenClaw 工具与任务：main-agent transcript 中的 `toolCall`，以及 `~/.openclaw/workspace/memory/tasks.json`与当日会话索引。
- OpenClaw 暂无可信本机额度源，因此额度显示为 `--`，不把“不可用”伪装成 0。
- Claude Code：`~/.claude/projects/**/*.jsonl`、本机 stats cache、statusLine 快照和任务元数据；未选中时不扫描 `~/.claude`。
- Hermes：默认 profile 的 `~/.hermes/state.db` 中 session/message 结构化字段；自然日趋势按会话最后活跃时间近似归桶，明确的 Codex-backed session 从 Hermes token 中排除；未选中时不打开数据库。
- 更新检测：仅手动触发时访问 GitHub Releases API。

当前 Codex 额度 API 暴露的是滚动窗口百分比和重置时间，不暴露绝对配额数量；第二 Agent 数据均为本机记录统计，不代表任何官方账单。

## 常见问题

### codexU 是官方 OpenAI 产品吗？

不是。codexU 是一个非官方的本地 macOS 工具，用于读取本机 Codex app-server 和本机 `~/.codex/` 数据。

### codexU 会上传我的 Codex 线程或 usage 数据吗？

不会。codexU 只在本机读取 Codex 账户额度、本机 SQLite usage 和 automation 元数据，不把这些数据上传到第三方服务。自动更新检测只请求 GitHub Release 的公开版本元数据，不携带本机 usage、线程、路径、日志或账户数据。

### 为什么显示的是剩余百分比，而不是绝对额度？

当前 Codex 本地 API 暴露的是滚动窗口已用百分比和重置时间，不暴露绝对额度数量，所以 codexU 展示的是 5 小时和 7 天窗口的剩余百分比。

### 支持 Intel Mac 吗？

支持。Intel Mac 下载 `codexU-<version>-mac-x86_64.dmg`。从源码打包时使用 `make release-intel`，或在支持对应 target 的机器上使用 `TARGET_TRIPLE="x86_64-apple-macos14.0"`。

### 可以同时显示 OpenClaw、Claude Code 和 Hermes 吗？

不能。v1.1.0 的模型是“Codex 固定 + 一个第二 Agent”：在设置中三选一，避免后台扫描未使用的工具，也让 token 归属和菜单栏保持清晰。新增 Agent 通过独立 Provider 接入，不需要改动现有 Provider 的统计。

## License

MIT. See [LICENSE](LICENSE).
