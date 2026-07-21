# codexU v1.1.5

这是一次修复 Codex 对话分支 token 重复统计的稳定 patch，对应 [Issue #32](https://github.com/shanggqm/codexU/issues/32)。从已有对话创建分支时，Codex 会把分支点之前的 token 事件带入新 session；此前 codexU 会把这些继承事件当作新用量再次累计。

## 主要更新

- 读取 session 的父子线程元数据，识别从已有对话创建的分支。
- 比较父子 session 的 token 事件公共前缀，剔除分支继承的历史，只统计分支点之后的新增用量。
- SQLite 回退统计、精细 `token_count` 统计、每日趋势和项目排行统一使用相同的去重基线。
- 普通会话、找不到父会话或事件前缀不一致时不做扣减，避免误删真实用量。
- token 事件身份使用紧凑双 64 位指纹；分支关系采用有界两遍扫描，不全量保留 session entry。
- 全局内存风险门禁新增 session entry 全量保留检查，继续维持缓存数量、字节和工作集释放边界。
- 保持本地优先和隐私边界：不新增网络请求、遥测或用户数据上传。

## 验证

- 使用真实 Codex 分支复现：新分支原始 SQLite 立即增加 2,325,691 tokens，修复后这部分继承历史不再进入展示统计。
- 通过 Token 归一化与分支公共前缀回归测试、统计时区自测和脱敏 `--dump-json` 探针。
- 通过全局内存风险门禁，并验证热缓存探针保持在秒级。
- 通过 Apple Silicon 与 Intel 双架构 DMG、checksum、挂载、Mach-O 架构和 codesign 验证。

## 安装包

- 内部构建号：24。
- Apple Silicon：`codexU-1.1.5-mac-arm64.dmg`
- Intel：`codexU-1.1.5-mac-x86_64.dmg`

## SHA-256

```text
0161f3c15237618ec25193f336db433508999e840b0b100aad45cf641fad3fa8  codexU-1.1.5-mac-arm64.dmg
13c717bbfd7db5b259a26ee683085687a5a8fb3a88fe2417a6689148e6ecca70  codexU-1.1.5-mac-x86_64.dmg
```

本次安装包使用仓库默认签名流程构建，未执行 Apple notarization。
