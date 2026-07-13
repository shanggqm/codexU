#!/usr/bin/env bash
set -euo pipefail

: "${APP_NAME:?APP_NAME is required}"
: "${DISPLAY_NAME:?DISPLAY_NAME is required}"
: "${VERSION:?VERSION is required}"
: "${ARCH_NAME:?ARCH_NAME is required}"
: "${BUILD_DIR:?BUILD_DIR is required}"
: "${DIST_DIR:?DIST_DIR is required}"
: "${APP_DIR:?APP_DIR is required}"
: "${DMG_PATH:?DMG_PATH is required}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR" >&2
  exit 1
fi

DMG_ROOT="$BUILD_DIR/dmg-root"
VOLUME_NAME="$DISPLAY_NAME"
TMP_DMG="$DMG_PATH.tmp.dmg"

case "$ARCH_NAME" in
  arm64)
    ARCH_LABEL="Apple Silicon Mac (arm64)"
    ;;
  x86_64)
    ARCH_LABEL="Intel Mac (x86_64)"
    ;;
  *)
    ARCH_LABEL="macOS ($ARCH_NAME)"
    ;;
esac

rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

ditto "$APP_DIR" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

cat > "$DMG_ROOT/README.txt" <<README
${DISPLAY_NAME} ${VERSION}
适用机型: ${ARCH_LABEL}

安装:
1. 将 ${APP_NAME}.app 拖到 Applications 文件夹。
2. 打开 Applications 里的 ${DISPLAY_NAME}。
3. 如果 macOS 提示来自互联网下载，请在系统设置 > 隐私与安全性中允许打开。

依赖:
- macOS 13 或更新版本。
- 本机已安装并登录 Codex。
- Codex 至少使用过一次，以便生成 ~/.codex/state_5.sqlite。

权限:
- 全局快捷键 Command + U 用于显示/隐藏主窗口。
- 菜单栏图标可以打开 Runtime 浮窗、主窗口、设置或退出应用。

隐私:
- 本应用只读取本机 Codex app-server、~/.codex 和可选 ~/.claude 的本地统计数据。
- 不读取认证 token，不上传数据。
README

rm -f "$DMG_PATH" "$TMP_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$TMP_DMG"

mv "$TMP_DMG" "$DMG_PATH"

if [[ -n "${DMG_SIGN_IDENTITY:-}" && "${DMG_SIGN_IDENTITY:-}" != "-" ]]; then
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
echo "Created $DMG_PATH"
