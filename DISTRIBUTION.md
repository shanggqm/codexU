# codexU Distribution

This app is distributed outside the Mac App Store as a downloadable DMG. The repository also contains an independent Windows desktop implementation distributed as MSI and NSIS installers.

## Supported targets

- macOS 13 or later.
- Apple Silicon Macs with the `arm64` DMG.
- Intel Macs with the `x86_64` DMG.
- Windows 10/11 x86_64 with the MSVC toolchain. Windows ARM64 is not packaged yet.
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
make clean release TARGET_TRIPLE="x86_64-apple-macos13.0"
```

## Release DMG with checksum

```sh
make release
```

This creates the DMG and a `SHA-256` checksum file next to it.

## Windows local installer

The Windows package uses Tauri's MSI and NSIS targets. Run this on a Windows machine or Windows CI runner with Rust, rustup, Node.js, and npm installed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows-release.ps1 -Version 1.3.2
```

The script pins the MSVC Rust toolchain, runs the Windows workspace tests and frontend build, builds both installers, and writes these files under `dist/windows/`:

```text
codexU-<version>-windows-x86_64.msi
codexU-<version>-windows-x86_64.msi.sha256
codexU-<version>-windows-x86_64-setup.exe
codexU-<version>-windows-x86_64-setup.exe.sha256
```

The current Tauri configuration uses the WebView2 download bootstrapper. The Windows installers are not code-signed by this repository's default workflow; public distribution should add Windows code-signing credentials and verification before claiming a signed release.

The repository target is also available as:

```sh
make release-windows VERSION=1.3.2
```

## Deterministic release verification

For a formal release, prefer the repository wrappers instead of manually repeating build and verification commands:

```sh
make memory-risk-check
sed -n '1,240p' build/memory-risk/report.md
```

This mandatory gate scans the full production source tree for unbounded stream reads, app-server pipe reads that wait for a full fixed-size buffer instead of returning partial responses, process-pipe lifecycle errors, repeating callback retention, missing observer cleanup, unbounded caches or pending-request collections, and parent-path traversal without explicit root termination or cycle guards. Review the generated inventory before continuing. A failure blocks all later release work and must not be bypassed.

```sh
make release-package
```

This reruns the memory-risk gate, runs the self-tests including the macOS 13 Claude Skill root-parent regression, builds both architectures, verifies both DMGs and checksums, mounts each image, checks the embedded Mach-O architecture, and verifies the app signature.

After copying the generated SHA-256 values into `docs/release-notes-v<version>.md`, run:

```sh
make release-check
```

This reruns the memory-risk gate and validates version/document consistency, release assets, checksums, release notes, and tag/release conflicts. It intentionally does not tag, push, or publish; those external writes remain explicit steps documented in `AGENTS.md` and `.agents/skills/codexu-release/SKILL.md`.

## Dual-platform release workflow

After updating the version and release notes, run the existing macOS package gate on a Mac:

```sh
make release-package VERSION=<version>
```

Before creating the final release commit and annotated tag, the workflow can build Windows installers from the reviewed source branch without committing checksum placeholders:

```sh
gh workflow run release-packages.yml --ref <source-branch> -f version=<version> -f platform=windows
```

Download the Windows artifact, combine it with the locally verified macOS DMGs, fill all four hashes into the release notes, and run both `make release-cross-platform-check` and `make release-check`. Then commit the final release metadata, push `main` and the annotated tag. Tag builds run both platforms and the final Ubuntu checksum aggregation; a manual dispatch defaults to `platform=all`.

```sh
make release-cross-platform-check VERSION=<version>
```

The workflow intentionally produces artifacts but does not create or publish a GitHub Release. After reviewing the verified artifact bundle, create the release manually with these eight exact assets: four installers and their four `.sha256` files. This keeps tag, release notes, and publication as explicit human-controlled steps.

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
