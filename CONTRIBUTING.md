# Contributing

Thanks for helping improve codexU.

## Development

Initialize the project-local skills for Codex, Cursor, and Claude Code. The
canonical content stays under `.agents/skills`; `.codex/skills`,
`.cursor/skills`, and `.claude/skills` are compatibility symlinks only:

```sh
./scripts/init-agent-skills.sh
./scripts/init-agent-skills.sh --apply
```

Build the app:

```sh
make build
```

Run the global shortcut validation and exclusive-conflict self-test:

```sh
build/codexU.app/Contents/MacOS/codexU --self-test-global-shortcut
```

Run palette package validation and rendering tests:

```sh
make test-palettes
./scripts/test-status-item.sh
```

Run locally:

```sh
make run
```

Check the local data reader:

```sh
make probe
```

For macOS SSH usage changes, also run `make test-remote-usage` and, after building,
`python3 scripts/test-remote-usage-integration.py`. The latter uses synthetic
sessions and `--dump-json --skip-account`, which skips the account app-server
and its database migrations. No real SSH server is required for these tests.

## Pull Requests

- Keep changes focused on one bug fix or feature.
- Run `make build` before opening a pull request.
- Update `README.md` or `DISTRIBUTION.md` when behavior, installation, permissions, or packaging changes.
- Avoid committing local build outputs from `build/` or `dist/`.

## Palette Contributions

Palette contributions are declarative packages under `Resources/Palettes/<stable-id>/`; do not add palette-specific branches to Swift views. A package must include light and dark semantic tokens, Chinese and English metadata, source/license information, and an asset manifest. SVG assets are optional and must stay within the static safety subset.

Start from the controlled template rather than copying product code:

```sh
cp -R contrib/palette-template Resources/Palettes/community.example
```

Rename the destination and update `manifest.id` together. The app never scans user directories and does not provide color pickers or local side-loading; a palette becomes available only after repository review and inclusion in a signed release.

Before opening a palette PR:

- Follow [Palette Package v1](docs/PALETTE_PACKAGES.md).
- Verify both Light and Dark appearances in the 820 × 720 main window, settings window, Runtime popover, and all three menu-bar density modes.
- Run `make test-palettes` and `./scripts/test-status-item.sh`.
- Include screenshots for both appearances and explain the cultural/design source without claiming unsupported artifact accuracy.
- Keep status, surface, text, and control colors unchanged; a palette may only provide the public configurable roles.
- Remove no required files and add no undeclared files. The validator enforces the Palette Package v1 path whitelist, README/LICENSE presence, and non-executable resource boundary.

## Privacy

codexU reads local Codex files from `~/.codex/`. Do not include real account data, thread titles, local paths, screenshots with private task names, or local SQLite data in issues or pull requests.
