# codexU Distribution

This app is distributed outside the Mac App Store as a downloadable DMG.

## Supported targets

- macOS 14 or later.
- Apple Silicon Macs with the `arm64` DMG.
- Intel Macs with the `x86_64` DMG.
- `make release` builds the current host architecture by default. Use the explicit architecture targets below when preparing GitHub Release artifacts.
- A local Codex installation and a signed-in Codex account are required for account quota data.

## Local unsigned DMG

Use this for private testing or installation on your own machines:

```sh
make clean dmg
```

The artifact is written to:

```text
dist/codexU-<version>-mac-<arch>.dmg
```

Because this build is ad-hoc signed, another Mac may show a Gatekeeper warning on first launch.

If macOS blocks the app, open **System Settings > Privacy & Security**, scroll to
the **Security** section, click **Open Anyway** for `codexU.app`, then confirm
with Touch ID or your password. Finder right-click > **Open** also shows the
manual allow prompt.

To build an Intel-only artifact from a compatible toolchain:

```sh
make release-intel
```

This writes `dist/codexU-<version>-mac-x86_64.dmg` and its `.sha256` file.

To build an Apple Silicon artifact explicitly:

```sh
make release-arm64
```

To build both Release DMGs in one command:

```sh
make release-all
```

You can still override the target triple directly when needed:

```sh
make clean release TARGET_TRIPLE="x86_64-apple-macos14.0"
```

## Release DMG with checksum

```sh
make release
```

This creates the DMG and a `SHA-256` checksum file next to it.

## Deterministic release verification

For a formal release, prefer the repository wrappers instead of manually repeating build and verification commands:

```sh
make release-package
```

This runs the self-tests, builds both architectures, verifies both DMGs and checksums, mounts each image, checks the embedded Mach-O architecture, and verifies the app signature.

After copying the generated SHA-256 values into `docs/release-notes-v<version>.md`, run:

```sh
make release-check
```

This validates version/document consistency, release assets, checksums, release notes, and tag/release conflicts. It intentionally does not tag, push, or publish; those external writes remain explicit steps documented in `AGENTS.md` and `.codex/skills/codexu-release/SKILL.md`.

## Developer ID signed build

For broad distribution outside the App Store, sign with a Developer ID Application certificate:

```sh
make clean dmg SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DMG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

The app bundle is signed with hardened runtime and timestamping when `SIGN_IDENTITY` is not `-`.

## Notarization

After building with a Developer ID certificate, notarize and staple the DMG:

```sh
make notarize \
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DMG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  APPLE_ID="you@example.com" \
  TEAM_ID="TEAMID" \
  NOTARY_PASSWORD="app-specific-password"
```

`NOTARY_PASSWORD` should be an Apple app-specific password or a keychain profile value accepted by `xcrun notarytool`.

## Verify an artifact

```sh
hdiutil verify dist/*.dmg
hdiutil attach dist/*.dmg
codesign --verify --deep --strict "/Volumes/codexU/codexU.app"
```

For notarized releases, also run:

```sh
spctl -a -t open --context context:primary-signature -v dist/*.dmg
```

## Runtime dependencies

The app does not bundle Codex. It reads:

- `codex app-server` from the local Codex installation.
- `~/.codex/state_5.sqlite` for local token and thread statistics.
- `~/.codex/automations/**/automation.toml` for enabled automation tasks.

If Codex changes its app-server API or local SQLite schema, the widget should fail into a partial-data mode instead of blocking launch.
