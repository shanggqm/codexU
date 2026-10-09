# Windows 版本：Phase 4 Dashboard UI（当前）

当前 checkout 已包含 Phase 1/2 的本地数据管线和 Phase 4 Dashboard UI：

- Rust reader 读取本机 Codex transcript、`state_5.sqlite` 和 automation 元数据
- Tauri IPC、额度状态、用量、推理性能、任务、项目、Skills 和 AI Leadership Dashboard
- 中英文设置、Light/Dark/System 外观和六套语义 palette catalog
- Windows 原生 exact-HWND、后台不抢前台的视觉采集 workflow

## Windows Dashboard showcase

![codexU Windows AI Leadership dashboard](../docs/windows-port/showcase/assets/windows-glass-light-default-overview.png)

这是一张当前 Windows Web 实现的 AI Leadership 截图：Light 主题、default palette、
Playwright viewport `1440×900`。画面只展示聚合指标和领导力界面，不包含任务标题、项目名或本机路径。
它用于展示当前 Dashboard 的信息层级和玻璃表面，不作为真实 Tauri HWND、DPI、窗口层级或原生透明
路径的验收证据。

任务快照读取并展示：

- 线程标题、项目路径、模型、归档状态、Git 信息
- SQLite 读取失败时自动降级为 JSONL-only
- 标题优先使用 `title`，为空时回退到 `preview`，展示前归一化并截断到 48 个字符
- 工作区只展示路径尾名，automation 优先使用配置中的 `name`

### 历史读取与完整结果

历史文件或目录暂时不可读、日志记录不完整，或来源在读取期间发生变化时，本轮读取不会作为
完整历史发布，也不会把失败产生的空摘要写进有效缓存。应用保留同一数据来源的上次完整累计、
明细和 AI Leadership，并提示刷新重试；解锁后无需再次修改日志即可重新读取。

首次读取失败时显示加载失败；可确认的空来源仍显示暂无数据。切换数据来源或主动清缓存后，
不恢复前一个来源的历史。成功完整重读可以更新为较小的累计值。历史事实和每日归档在 SQLite
事务中提交，完整发布点不会因失败提前推进；推理缓存仍以临时文件写完后原子替换。
这些缓存是可重建的派生数据，不修改原始日志。

此保护适用于当前应用进程中已保存的完整快照；退出重开后的首页摘要恢复和独立刷新仍属于
后续首页加载改进。仍保留既有的 state SQLite 不可用时 JSONL-only 口径与来源提示。

### 增量历史与每日归档

Windows 使用 `codex/history-index.sqlite` 保存安全派生事实、逐来源检查点和按统计时区生成的
每日归档。没有变化的日志不重新解析；追加从已提交的完整行检查点续读，未结束的尾行保留为
待补全状态。文件截断、同大小改写或原子替换会重建该来源。检查点分批提交，程序中断后可续接，
只有本轮清单全部读完并通过来源核验才更新完整发布点。

增量路径使用文件身份、大小/mtime，以及有界的文件头和检查点边界摘要；不会在每次追加时
扫描全部旧字节。任意内部改写与追加同时发生时，使用明确的完整性扫描核验原始日志：

```powershell
.\target\release\codexu-probe.exe --verify-history-index --codex-root "<data-root>" --cache-dir "<cache-root>" --summary
```

原有整包 JSON 摘要缓存路径已退出，SQLite 索引可从原始日志重建。计数器区分累计与增量，
支持同一 turn 多次调用，cached input 属于 input 子集；相同逻辑会话的 live/archive 复制与明确
fork 的公共 token 前缀不重复计费。普通 runtime spawn 父子关系不视作复制历史。每日、月度、
趋势和归档使用相同统计时区，包括 DST 日界。

资源边界：主库页上限 256 MiB，受管理的索引及旁文件预算 1 GiB，事实物化上限 500,000 条，
每来源未完成任务上限 1,024 个。超限、索引占用或写入失败明确返回状态并保留同来源的完整值；
不会清理原始日志。每日旧归档以每批最多 256 行回收，保留当前和上一完整发布版本；SQLite
读事务仍在使用的快照会阻止删除提交。索引页可重用，不为每次回收做整库压缩。

```powershell
# 定向回归
cargo test -p codexu-core --test incremental_history
# 显式的 500 来源 / 50,000 事件 Release 探针（默认 suite 不自动运行）
cargo test --release -p codexu-core --test incremental_history_scale -- --ignored --nocapture --test-threads=1
```

## 安装（推荐）

Windows 用户可以直接打开[最新 GitHub Release](https://github.com/shanggqm/codexU/releases/latest)，在
Assets 中下载带有 `-setup.exe` 后缀的 NSIS 安装包：

1. 下载 `codexU-<version>-windows-x86_64-setup.exe`。
2. 双击安装包并按向导完成安装；它使用当前用户安装，不需要管理员权限。
3. 从开始菜单或安装目录启动 `codexU`。

Release 页面同时提供 MSI 安装包和对应的 `.sha256` 文件。需要通过 Windows Installer 管理安装时选择 MSI；
需要快速完成当前用户安装时，优先选择 NSIS 安装包。仓库默认发布包尚未进行代码签名，Windows 首次运行时
可能显示安全提示。

## 快速开始

Windows 工作区使用 Node.js 22.12 或更新版本和 MSVC ABI。首次在当前检出目录开发时，
安装并设置项目级 toolchain override：

```powershell
rustup toolchain install stable-x86_64-pc-windows-msvc --profile minimal --component rustfmt
rustup override set stable-x86_64-pc-windows-msvc
```

该 override 只作用于当前 `windows/` 目录，不修改全局默认 toolchain。仓库不提交
`rust-toolchain.toml`，因为只写版本号时，rustup 会沿用用户的 default host，在配置为
GNU 的 Windows 环境中意外选择 GNU ABI，并额外要求系统提供 `dlltool.exe`。

Windows release 构建会先更新 stable MSVC toolchain，再执行格式检查、测试和打包。

```powershell
cd windows
cargo build --release

# 使用默认路径（~/.codex/state_5.sqlite）
$env:RUST_LOG="info"
.\target\release\codexu-probe.exe --summary

# 指定 Codex 数据根
.\target\release\codexu-probe.exe --codex-root "$env:USERPROFILE\.codex" --summary
```

## 验证

```powershell
# Rust workspace tests
cargo +stable-x86_64-pc-windows-msvc test --workspace
```

### Web 验证

默认 Playwright 运行使用仓库内的合成 fixture，因此在没有本机 Codex 历史的干净 runner 上也可复现。
只有显式设置 `CODEXU_VISUAL_LIVE=1` 时，才以只读方式加载当前机器的本地聚合数据；两种模式的截图和
manifest 都只写入 Git 忽略的 `.local-artifacts/`。

```powershell
cd windows\apps\codexu-tauri\web
npm ci
npm run build
npm run test:contracts
npm run test:visual

# 可选：以本机只读数据复核单个 surface
$env:CODEXU_VISUAL_LIVE="1"
$env:CODEXU_VISUAL_SURFACE="inference"
npm run test:visual
Remove-Item Env:CODEXU_VISUAL_LIVE, Env:CODEXU_VISUAL_SURFACE
```

### 原生视觉验收

Dashboard 的正式 Windows 本机采集入口会构建真实 Tauri release 应用，并执行一次
最大化、exact HWND 的采集运行。Overview 仅采集一个顶部 viewport；Tasks、AI Leadership、
Usage 与 Skills 使用动态编号的 panel segments；Projects 仅采集一个最大化的首个 viewport。
采集实例保持最大化，但以 non-activating background tool window 运行：不改变用户当前前台窗口，
并从任务栏和 Alt-Tab 排除；正常启动 codexU 的窗口行为不变。
截图、日志和 WebView2 临时数据只写入
Git 忽略的 `.local-artifacts/`；当前契约不包含额外的 client sizes。

本轮 Windows V0 的原生视觉矩阵与 shell lifecycle 证据在按 build `26200` 归类的 Windows 11
环境完成；Windows 10 仍是支持目标，但未在本轮实机观测。该说明只描述本轮验收环境，
不把当前主机结果扩展为跨 OS 结论。

测试分三层：

1. `-PreflightOnly` 只检查依赖、脚本语法、窗口策略和输出边界，不构建、不启动窗口。
2. `Test-NativeVisualCaptureWorkflow.ps1` 检查采集 workflow 的静态契约，包括最大化、non-activating、保留前台窗口、后台 Z-order、tool window、任务栏/Alt-Tab 排除和精确 capture 参数。
3. `Test-NativeVisualCaptureCoverage.ps1` 构建并启动真实 Tauri release 应用，覆盖各 Dashboard surface，验证 exact HWND、真实截图、前台窗口未改变和最终进程清理。

```powershell
cd ..

# 不启动 app 的快速检查
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\Capture-NativeVisuals.ps1 -PreflightOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\tests\Test-NativeVisualCaptureWorkflow.ps1

# 真实窗口覆盖测试（会构建、启动、截图并清理）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\tests\Test-NativeVisualCaptureCoverage.ps1

# 正式采集
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\Capture-NativeVisuals.ps1

# 只采集 Skills 的聚焦运行
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\scripts\Capture-NativeVisuals.ps1 -Surface Skills
```

Coverage 运行速度不是当前验收重点；重点是它不会抢焦点或覆盖用户正在使用的窗口。运行边界、DPI 说明、精确 PID 清理规则和人工验收清单见
[`docs/windows-port/WINDOWS_NATIVE_VISUAL_WORKFLOW.md`](../docs/windows-port/WINDOWS_NATIVE_VISUAL_WORKFLOW.md)。

## 工程结构

```text
windows/
├── Cargo.toml
├── README.md
└── crates/
    ├── codexu-core/
    │   ├── Cargo.toml
    │   └── src/
    │       ├── lib.rs
    │       ├── models/
    │       │   ├── mod.rs
    │       │   ├── usage.rs
    │       │   ├── runtime.rs
    │       │   └── leadership.rs
    │       └── readers/
    │           ├── mod.rs
    │           ├── common.rs              ← 聚合、缓存、成本估算
    │           ├── codex_state.rs         ← 新增：state_5.sqlite 读取
    │           ├── codex_transcript.rs    ← Codex JSONL + 元数据富化
    │           └── claude_transcript.rs   ← Claude Code JSONL（保留，待激活）
    └── codexu-cli/
        ├── Cargo.toml
        └── src/
            └── main.rs                    ← CLI 入口
```

## 后续开发方向

1. 扩展 Windows 10 与不同 DPI 环境下的原生视觉验证。
2. 逐项处理布局、数据边界、安装体验和验收证据等其他差异。
