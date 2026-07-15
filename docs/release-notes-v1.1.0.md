# codexU v1.1.0

Codex 现在固定保留，可在设置中选择一个第二 Agent：OpenClaw、Claude Code 或 Hermes。

## 主要变化

- 第二 Agent 单选：OpenClaw / Claude Code / Hermes；未选中的 Agent 不读取本机目录，也不进入聚合统计。
- 各算各的：明确属于 Codex 的 OpenClaw/Hermes 记录从第二 Agent token 中排除，Codex 本机记录继续归入 Codex。
- 任务来源：任务卡显示 Codex、OpenClaw、Claude Code 或 Hermes；Codex 线程详情支持“在 Codex 中打开”。
- 本机状态：显示 CPU、物理内存和温度/热状态；无公开温度传感器时不伪造数值。
- Hermes：读取默认 profile 的 `~/.hermes/state.db` 结构化字段；自然日趋势按会话最后活跃时间近似归桶。
- 发布清理：README 已换成 v1.1.0 真实截图，旧截图和上游推广二维码内容不再随本分支发布。

## 开源来源与致谢

- 基于 [shanggqm/codexU](https://github.com/shanggqm/codexU) v1.0.5，MIT License。
- OpenClaw 接入与品牌资源来自 [openclaw/openclaw](https://github.com/openclaw/openclaw)，MIT License。
- Hermes 接入、存储格式和 Logo 来自 Nous Research 的 [Hermes Agent](https://github.com/NousResearch/hermes-agent)，MIT License。
- Claude Code Provider 与图标继承自上游 codexU；Claude Code 是 Anthropic 产品。

完整声明见 `THIRD_PARTY_NOTICES.md`。本项目是非官方工具，与 OpenAI、Anthropic、OpenClaw 或 Nous Research 均无隶属或背书关系。

## 安装包

- Apple Silicon: `codexU-1.1.0-mac-arm64.dmg`
  - SHA-256: `2ccc263392f20bf7255bd1c59352d8a2a42221cd2052add7179751d73f1a2207`
- Intel: `codexU-1.1.0-mac-x86_64.dmg`
  - SHA-256: `71599542503c434d4d16f260944065a89dde3d7e74b41c5631fcbb25e306fbde`

安装包使用 ad-hoc 签名，未执行 Apple notarization。首次打开时请按 README 的“隐私与安全”说明手动允许。
