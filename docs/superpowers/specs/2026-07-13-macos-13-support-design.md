# macOS 13 Support Design

## Goal

Make macOS 13.0 the official minimum supported version for codexU on both Intel and Apple Silicon, and contribute the change upstream as a focused, reviewable pull request.

## Scope

The change aligns the build target, application metadata, distribution guidance, and release validation around macOS 13.0. It does not change product behavior, UI, application version numbers, or release notes.

The implementation will update:

- `Makefile` so the default deployment target is macOS 13.0 and both architecture-specific target triples inherit that value.
- `Resources/Info.plist` so `LSMinimumSystemVersion` is 13.0.
- `README.md`, `README.en.md`, and `DISTRIBUTION.md` so requirements and source-build examples state macOS 13.0.
- `scripts/package-dmg.sh` so the generated DMG instructions state macOS 13.0.
- Release validation so future changes cannot silently make the build configuration, bundle metadata, and documentation disagree.

The implementation will not update `CHANGELOG.md`, release notes, or bundle version fields. Those changes belong to the upstream maintainer's release process.

## Compatibility Strategy

The current Swift sources contain no known macOS 14-only APIs. The implementation therefore lowers the declared deployment target without adding speculative availability branches.

If compilation against macOS 13 identifies an actual newer API, the implementation will add the smallest possible `#available` check and macOS 13 fallback at that call site. It will not introduce a general compatibility abstraction without a demonstrated need.

## Consistency Check

A lightweight repository script will verify that:

- The Makefile default deployment target is exactly `13.0`.
- `LSMinimumSystemVersion` is exactly `13.0`.
- Intel and Apple Silicon target triples continue to derive from the shared deployment target.
- Supported-version statements and explicit target-triple examples in maintained installation and distribution documentation do not require macOS 14.
- The generated DMG instructions state macOS 13.0 or later.

Failures will identify the mismatched file and expected value. The check will run from the existing release verification flow so configuration drift is caught before packaging.

## Verification

Implementation will follow a red-green cycle: the new consistency check must fail against the existing macOS 14 configuration before production configuration is changed, then pass after all supported-version declarations are aligned.

Verification will include:

- The new macOS compatibility consistency check.
- Existing parser, time-zone, status-item, update, and other repository self-tests exposed by the current build and scripts.
- Compilation for `arm64-apple-macos13.0` and `x86_64-apple-macos13.0` where the installed SDK and toolchain permit it.
- Inspection of the resulting Mach-O minimum OS version and `LSMinimumSystemVersion`.
- Launch and `--dump-json` execution on the available macOS 13.1 Intel host.
- `git diff --check`.

Any validation that cannot be completed because the local Swift compiler, SDK, signing setup, or architecture support is unavailable will be stated explicitly in the pull request rather than inferred as passing.

## Pull Request Shape

The contribution will use a dedicated branch and focused commits. The pull request will explain the motivation, list the synchronized compatibility declarations, report exact verification results, and call out any toolchain-limited checks. It will not include generated `build/` or `dist/` artifacts.
