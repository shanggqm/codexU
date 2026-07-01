# codexU

[English](README.en.md)

codexU 是一个 macOS 桌面小组件，用来查看 OpenAI Codex / ChatGPT Codex 的额度窗口、token 用量和今日任务状态。它把常用信息放在桌面上，帮助你快速判断剩余额度、重置时间和当天工作进展。

![codexU 桌面小组件截图](docs/screenshot-0.2.0.png)

## 适合谁

- 经常使用 OpenAI Codex、Codex CLI 或 Codex 桌面应用的开发者。
- 需要快速查看 5 小时/7 天额度、token 用量和重置时间的 ChatGPT Pro / Team 用户。
- 想在桌面查看 Codex 使用状态、减少反复打开浏览器或终端的人。

## 功能

- 展示 Codex 5 小时和 7 天额度的剩余比例、已用比例和重置时间。
- 汇总今日、近 7 天和累计 token 用量，并细分未缓存输入、命中缓存输入和输出。
- 按 OpenAI API token 价格估算本月 API 等效价值，并在 Plus、Pro 100、Pro 200 和满额月价值之间展示进度刻度。
- 从本机 Codex 线程和启用中的 automations 生成今日任务看板。
- 按进行中、待处理、定时、完成四类组织任务。
- 默认贴在桌面层，支持 `Command + U` 一键唤到前台。
- 支持中文和英文界面，可根据系统时区自动选择，也可通过顶部 `中 | EN` 手动切换。
- 支持自动、浅色和深色外观模式，默认跟随系统设置，也可通过顶部外观切换手动指定。
- 本地读取数据，不上传 usage、线程或账户数据到第三方服务。

## 快捷键和操作

- `Command + U`：在桌面层和前台层之间切换小组件。
- 菜单栏仪表图标：点击后执行和 `Command + U` 相同的切换操作。
- 顶部外观切换：在自动、浅色和深色模式之间切换；自动模式跟随系统设置。
- 顶部 `中 | EN`：切换中文或英文界面，手动选择会在下次启动时保留。
- 右上角刷新按钮：立即刷新额度、token 统计、趋势图和任务看板。
- 右上角关闭按钮：退出 codexU。
- 拖动小组件背景：移动小组件位置。

## 首次安装：隐私与安全

codexU 目前通过 GitHub Release 的 DMG 安装包分发，不经过 Mac App Store。第一次打开时，macOS 可能会拦截，需要手动允许：

1. 打开 `codexU.app` 一次。如果系统提示无法打开，先取消弹窗。
2. 打开 **系统设置 > 隐私与安全性**。
3. 在 **安全性** 区域找到 `codexU.app`，点击 **仍要打开**。
4. 使用 Touch ID 或密码确认，然后点击 **打开**。

也可以在 Finder 中右键点击 `codexU.app`，选择 **打开**，再确认系统安全提示。

codexU 需要读取本机 `~/.codex/` 下的 Codex 数据。如果 macOS 弹出文件或文件夹访问授权，请允许访问，否则小组件无法读取本机 usage、线程和自动化任务信息。

## 安装

从 GitHub Release 下载与你的 Mac 芯片匹配的安装包：

- Apple Silicon：`codexU-<version>-mac-arm64.dmg`
- Intel：`codexU-<version>-mac-x86_64.dmg`

1. 打开 DMG。
2. 将 `codexU.app` 拖到 `Applications` 文件夹。
3. 从 `Applications` 打开 codexU。
4. 按上面的 **首次安装：隐私与安全** 步骤完成手动放行。

## 运行要求

- macOS 14 或更新版本。
- 本机已安装 Codex。
- 已登录 Codex 账户，额度信息才会显示。
- Codex 至少使用过一次，以便生成 `~/.codex/state_5.sqlite`。
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
build/codexU.app/Contents/MacOS/codexU --dump-local-json
build/codexU.app/Contents/MacOS/codexU --dump-app-server-json
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
dist/codexU-0.2.0-mac-arm64.dmg
dist/codexU-0.2.0-mac-arm64.dmg.sha256
dist/codexU-0.2.0-mac-x86_64.dmg
dist/codexU-0.2.0-mac-x86_64.dmg.sha256
```

Developer ID 签名和 Apple notarization 流程见 [DISTRIBUTION.md](DISTRIBUTION.md)。

## 数据来源

- 账户与额度：`codex app-server` 的 `account/read`、`account/rateLimits/read`。
- 本机 token 总量：`~/.codex/state_5.sqlite`。
- 精细 token 拆分：`~/.codex/sessions/**/rollout-*.jsonl` 和 `~/.codex/archived_sessions/*.jsonl` 中的 `token_count` 事件。
- 今日任务看板：本机 SQLite 中未归档和今日归档的 Codex 线程。
- 定时任务：`~/.codex/automations/**/automation.toml` 中启用的 automation 元数据。

当前 Codex 额度 API 暴露的是滚动窗口百分比和重置时间，不暴露绝对配额数量。更完整的数据口径和回退策略见 [RESEARCH.md](RESEARCH.md)。

## 常见问题

### codexU 是官方 OpenAI 产品吗？

不是。codexU 是一个非官方的本地 macOS 工具，用于读取本机 Codex app-server 和本机 `~/.codex/` 数据。

### codexU 会上传我的 Codex 线程或 usage 数据吗？

不会。codexU 只在本机读取 Codex 账户额度、本机 SQLite usage 和 automation 元数据，不把这些数据上传到第三方服务。

### 为什么显示的是剩余百分比，而不是绝对额度？

当前 Codex 本地 API 暴露的是滚动窗口已用百分比和重置时间，不暴露绝对额度数量，所以 codexU 展示的是 5 小时和 7 天窗口的剩余百分比。

### 支持 Intel Mac 吗？

支持。Intel Mac 下载 `codexU-<version>-mac-x86_64.dmg`。从源码打包时使用 `make release-intel`，或在支持对应 target 的机器上使用 `TARGET_TRIPLE="x86_64-apple-macos14.0"`。

## License

MIT. See [LICENSE](LICENSE).
