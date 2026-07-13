---
name: codexu-release
description: codexU repository release SOP for 发布新版、发版、patch/beta release, packaging, tagging, pushing, and publishing a GitHub Release, including changelog/readme updates, DMG asset checksums, GitHub Release creation, and recovery from rejected pushes or stale tags.
---

# codexU Release SOP

## Scope

Run this skill from the repository root. Treat the release as a real public publish: verify the current remote state first, keep unrelated user changes out of release commits, and report exactly what was built, pushed, and released.

Do not trust a remembered "latest" version. Always confirm the current tag and release state with GitHub before choosing the next version.

## Preflight

1. Inspect the worktree and branch:

```sh
git status --short
git branch --show-current
git remote -v
```

If unrelated files are dirty, do not stage or revert them. Either keep the release scoped to known release files or ask before mixing them into the release commit.

2. Confirm GitHub access and current releases:

```sh
gh --version
gh auth status
gh repo view --json nameWithOwner,url
gh release list --limit 10
git fetch origin --tags
```

3. Verify that the target `v<version>` tag and GitHub Release do not already exist unless the task is explicitly to repair or replace them.

## Versioning

Use these conventions unless the user specifies otherwise:

- Version string: `<major>.<minor>.<patch>` or `<major>.<minor>.<patch>-betaNN`.
- Git tag: `v<version>`.
- Release title: `codexU v<version>`.
- Release commit: `chore(release): prepare v<version>`.
- Beta releases use `gh release create --prerelease`.

Update `Resources/Info.plist`:

- `CFBundleShortVersionString` to `<version>`.
- `CFBundleVersion` to the next build number.

Validate the plist after editing:

```sh
plutil -lint Resources/Info.plist
plutil -p Resources/Info.plist | rg "CFBundleShortVersionString|CFBundleVersion" -C 2
```

## Documentation Updates

Update only the release-relevant files unless the user asks for broader docs:

- `CHANGELOG.md`: add the new release section and date.
- `README.md`: update current version, download links, and visible release notes in Chinese.
- `README.en.md`: update current version, download links, and visible release notes in English.
- `docs/release-notes-*.md`: update the release notes used by `gh release create --notes-file`.

For beta trains, prefer the existing train note file when present, such as `docs/release-notes-v1.0.0-beta.md`; otherwise create a version-specific notes file. Leave checksum placeholders until after packaging, then fill them with the actual SHA-256 values.

Run:

```sh
git diff --check
```

## Package

Run the deterministic repository wrapper:

```sh
make release-package
```

It runs the self-tests, builds both architectures, checks the DMGs and checksums, mounts both images, verifies Mach-O architecture, and verifies codesign. Do not manually repeat those steps unless debugging the wrapper.

Expect these assets for `<version>`:

```text
dist/codexU-<version>-mac-arm64.dmg
dist/codexU-<version>-mac-arm64.dmg.sha256
dist/codexU-<version>-mac-x86_64.dmg
dist/codexU-<version>-mac-x86_64.dmg.sha256
```

Verify checksums and copy the values into release notes:

```sh
cat dist/codexU-<version>-mac-arm64.dmg.sha256
cat dist/codexU-<version>-mac-x86_64.dmg.sha256
```

After filling release notes, run the metadata gate:

```sh
make release-check
```

Do not create the release commit or tag until this command passes.

Do not claim Apple notarization unless a notarization step was actually run. The current Makefile release flow uses the signing behavior configured in the repository.

## Commit, Tag, And Push

Stage release metadata and documentation, not generated DMGs unless repository policy changes:

```sh
git add Resources/Info.plist CHANGELOG.md README.md README.en.md docs/release-notes-*.md
git status --short
git commit -m "chore(release): prepare v<version>"
```

Before pushing, fetch and inspect divergence:

```sh
git fetch origin --tags
git log --oneline --left-right --cherry-pick origin/main...HEAD
```

If the remote contains the same logical commits with different hashes, rebase onto `origin/main`, then recreate any local tag that pointed to the pre-rebase commit:

```sh
git rebase origin/main
git tag -d v<version>  # only if the local tag points at the old commit
git tag -a v<version> -m "codexU v<version>"
```

Do not force-push `main` or delete remote tags without explicit user approval. After the branch and tag are correct:

```sh
git push origin main
git push origin v<version>
```

## Create GitHub Release

Create the GitHub Release with the exact packaged assets:

```sh
gh release create v<version> \
  dist/codexU-<version>-mac-arm64.dmg \
  dist/codexU-<version>-mac-arm64.dmg.sha256 \
  dist/codexU-<version>-mac-x86_64.dmg \
  dist/codexU-<version>-mac-x86_64.dmg.sha256 \
  --title "codexU v<version>" \
  --notes-file docs/release-notes-<notes>.md \
  --prerelease
```

Omit `--prerelease` only for stable releases. If a release already exists, inspect it first and use `gh release edit` only when the user intends an update.

## Verify And Report

Verify the published release:

```sh
gh release view v<version> --json tagName,name,isPrerelease,isDraft,url,assets,publishedAt,targetCommitish
git status --short
```

Some `gh` versions do not support `isLatest`; remove unsupported JSON fields rather than treating that as a release failure.

Report these facts to the user:

- Version, build number, tag, and release URL.
- Commit hash pushed to `main`.
- Uploaded asset names and SHA-256 values.
- Validation/build commands that ran.
- Any limitation, such as ad-hoc signing or no notarization.

## Recovery Notes

- Push rejected: run `git fetch origin`, inspect divergence with `git log --left-right --cherry-pick`, rebase if the remote has equivalent commits, recreate the local tag if needed, then push again.
- Local stale tag: delete and recreate only the local tag after confirming it points to an old pre-rebase commit.
- Remote tag or release conflict: stop and inspect with `git ls-remote --tags origin v<version>` and `gh release view v<version>`. Do not overwrite remote state without explicit user approval.
- Build failure: fix the underlying source or packaging issue, rerun `make release-all`, then regenerate checksums before publishing.
