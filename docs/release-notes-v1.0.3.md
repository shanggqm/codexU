# codexU v1.0.3

本次 patch 版本修复每日 token 口径不一致与手动刷新重复点击问题，并补充可配置统计时区。

## 主要更新

- 新增跟随系统、UTC 日界线和固定 IANA 时区三种统计模式。
- Codex、Claude Code、趋势、今日任务与 SQLite 回退统一使用所选统计时区。
- 时区切换提供加载/完成反馈，并缓存最近使用的时区快照。
- 菜单栏、Runtime 卡片和主窗口统一优先使用 `token_count` 精细今日用量。
- 修复刷新期间重复点击导致结果被丢弃、完整刷新重复执行的问题。
- 统一 K/M/B token 格式化，并增加时区、DST、格式化及回退口径测试。

## 安装包

- Apple Silicon：`codexU-1.0.3-mac-arm64.dmg`
- Intel：`codexU-1.0.3-mac-x86_64.dmg`

## SHA-256

```text
eb6f5130cf4b6b219653683272d6a7ec21bea3ca2cb8e9e45ccd97fec2de0d10  codexU-1.0.3-mac-arm64.dmg
bf0521261234f7c5e68c1d644c7a3a0205ff96bd1ee62a8da428b037c9c36dc1  codexU-1.0.3-mac-x86_64.dmg
```

本次安装包使用仓库默认签名流程构建，未执行 Apple notarization。
