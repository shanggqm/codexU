# AGENTS.md

本文件是 codexU 的长期协作规范。它只记录稳定原则、项目边界和必要流程，不记录某次功能的临时方案。

## 项目边界

codexU 是本地 macOS 桌面小组件，用于查看 Codex 额度、用量、趋势和任务状态。

必须保持：

- 本地优先：数据来自用户本机和本机 Codex 状态。
- 隐私优先：不上传 usage、线程、路径、日志或账户数据。
- 工具属性：界面服务快速判断和持续扫视，不做营销化表达。
- Liquid Glass 原生感：优先使用系统玻璃材质、系统字体、SF Symbols 和语义色。

## 关键文档

- 产品说明：`README.md`、`README.en.md`
- 设计系统：`docs/DESIGN_SYSTEM.md`
- 功能需求：`docs/` 下的 PRD 文档
- 打包发布：`DISTRIBUTION.md`
- 安全边界：`SECURITY.md`
- 贡献约定：`CONTRIBUTING.md`

改动触及对应领域时，同步更新对应文档。不要把一次性实现细节写进长期规范。

## 代码结构

- 主实现：`Sources/CodexUsageWidget/main.swift`
- 资源与版本：`Resources/`
- 构建与发布：`Makefile`、`scripts/`
- 设计和产品文档：`docs/`

当前项目刻意保持轻量。新增文件、依赖或架构层级前，先判断是否真的降低复杂度。

## 工作原则

- 先理解现有模式，再修改代码。
- 优先复用已有组件、数据模型、视觉 token 和本地 helper。
- 改动保持聚焦，不把需求实现和无关重构混在一起。
- 不回滚用户已有改动，除非用户明确要求。
- 不提交或依赖 `build/`、`dist/`、`.build/` 等生成产物。
- 使用清晰、可解释的文案，不暴露内部字段名。

## UI 原则

UI 改动必须遵守 `docs/DESIGN_SYSTEM.md`。

核心约束：

- 不使用 emoji 作为界面图标。
- 不新增散落的硬编码颜色、间距和圆角。
- 保持 Liquid Glass 风格：轻盈、透明、有层级，但不能牺牲可读性。
- 颜色必须有职责：品牌、状态、数据或表面。
- 卡片、标题栏、列表行、图表和控件保持统一层级。
- 并列卡片必须对齐；内容刷新不能造成明显布局跳动。
- 小组件首屏不展示 prompt、回复正文、tool arguments 或 raw logs。

## 数据原则

- 区分官方数据、本地记录和本地估算。
- 估算值必须明确标注。
- 回退口径必须用用户能理解的语言解释。
- 缺失数据不伪造成 0；应表达为记录不足、不可用或暂无。
- tooltip 可以解释口径，但不能泄露敏感正文。

## 验证流程

常用命令：

```sh
make build
make probe
build/codexU.app/Contents/MacOS/codexU --dump-json
git diff --check
```

规则：

- 代码改动后运行 `make build`。
- 数据读取或聚合逻辑改动后运行 `make probe` 或 `--dump-json`。
- UI 改动后启动本地 app 进行人工检查。
- 文档-only 改动至少运行 `git diff --check`。

本地启动：

```sh
osascript -e 'quit app "codexU"' >/dev/null 2>&1 || true
open "build/codexU.app"
```

## 发布原则

准备发布时才更新版本号和发布说明。

发布必须遵循以下固定顺序，不得跳过：

1. **确认范围与远端**：检查工作树、当前分支、GitHub 登录、远端最新 tag/release；混合改动必须先确认归属。
2. **更新版本与文档**：更新 `Resources/Info.plist` 的短版本和递增 build number、`CHANGELOG.md`、`README.md`、`README.en.md`、`docs/release-notes-v<version>.md`。
3. **构建验证**：运行 `make release-package`。该命令统一执行自测、双架构 DMG 构建、checksum、DMG 挂载、Mach-O 架构和 codesign 验证。
4. **回填 checksum**：把 `dist/*.sha256` 的真实值写入 release notes，再运行 `make release-check`。
5. **提交与发布**：release commit 使用 `chore(release): prepare v<version>`；创建 annotated tag `v<version>`；fetch 并检查 `origin/main...HEAD` 后，显式 push `main` 和 tag，再用 release notes 与四个精确资产创建 GitHub Release。
6. **线上复核**：确认 Release 非 draft、stable/beta 属性正确、Latest 状态符合预期、四个资产上传成功、tag 指向 release commit，最后确认工作树清洁。

稳定约束：

- 不提交 `build/`、`dist/` 产物；DMG 只上传 GitHub Release。
- 不 force-push `main`，不覆盖远端 tag/release；冲突时停止并检查。
- 未实际执行 notarization 时，release notes 必须明确“未 notarize”，不得声称已公证。
- beta 使用 `--prerelease`；稳定 patch 不使用。
- 发布脚本只自动化确定性检查与打包，不自动 push/tag/create release，避免误发布。

发布相关文件至少包括：

- `Resources/Info.plist`
- `CHANGELOG.md`
- `DISTRIBUTION.md`
- `Makefile`

默认本地迭代不做版本 bump。

完整命令与故障恢复见 `.codex/skills/codexu-release/SKILL.md` 和 `DISTRIBUTION.md`。

## 最终回复

完成工作时说明：

- 改了什么。
- 验证了什么。
- 哪些事没有做或无法验证。

保持简洁，不复述无关实现细节。
