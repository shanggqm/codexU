# Contributing

Thanks for helping improve codexU.

## Development

Build the app:

```sh
make build
```

Run the global shortcut validation and exclusive-conflict self-test:

```sh
build/codexU.app/Contents/MacOS/codexU --self-test-global-shortcut
```

Run locally:

```sh
make run
```

Check the local data reader:

```sh
make probe
```

Run the CLI Proxy API quota parser and Management API simulation:

```sh
make test-cpa-quota
```

## Pull Requests

- Keep changes focused on one bug fix or feature.
- Run `make build` before opening a pull request.
- Update `README.md` or `DISTRIBUTION.md` when behavior, installation, permissions, or packaging changes.
- Avoid committing local build outputs from `build/` or `dist/`.

## Privacy

codexU reads local Codex files from `~/.codex/`. Do not include real account data, thread titles, local paths, screenshots with private task names, or local SQLite data in issues or pull requests.
