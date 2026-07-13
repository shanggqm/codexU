# macOS 13 Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make macOS 13.0 the official, consistently validated minimum deployment target for codexU on Intel and Apple Silicon.

**Architecture:** Keep one deployment-target source of truth in the Makefile and derive both architecture triples from it. Add a shell-level repository contract test that checks build configuration, bundle metadata, user-facing documentation, and DMG instructions, then run that contract from the existing release verification flow.

**Tech Stack:** GNU Make, Bash, PlistBuddy, Swift compiler target triples, macOS bundle metadata, Markdown.

## Global Constraints

- The minimum supported operating system is exactly macOS 13.0.
- Intel and Apple Silicon builds must both derive their target triple from the shared `DEPLOYMENT_TARGET` value.
- Product behavior, UI, application version numbers, changelog, and release notes remain unchanged.
- No generated `build/` or `dist/` artifacts are committed.
- Validation that the local SDK or toolchain cannot perform must be reported explicitly in the pull request.

---

## File Structure

- Create `scripts/test-macos-compatibility.sh`: repository contract test for all macOS minimum-version declarations.
- Modify `Makefile`: set the source-of-truth deployment target and expose the contract test as a make target.
- Modify `Resources/Info.plist`: align bundle launch metadata with the compiler deployment target.
- Modify `README.md`: update Chinese requirements and Intel target-triple example.
- Modify `README.en.md`: update English requirements and Intel target-triple example.
- Modify `DISTRIBUTION.md`: update supported targets and explicit packaging example.
- Modify `scripts/package-dmg.sh`: update the installation instructions embedded in DMGs.
- Modify `scripts/build-release-artifacts.sh`: execute the compatibility contract before building release artifacts.

### Task 1: Add the macOS compatibility contract and align every declaration

**Files:**
- Create: `scripts/test-macos-compatibility.sh`
- Modify: `Makefile:11-29,52-54`
- Modify: `Resources/Info.plist:27-28`
- Modify: `README.md:108-115,196-198`
- Modify: `README.en.md:81-88,169-171`
- Modify: `DISTRIBUTION.md:5-10,54-58`
- Modify: `scripts/package-dmg.sh:49-51`

**Interfaces:**
- Consumes: repository files rooted at the script's parent directory and `/usr/libexec/PlistBuddy`.
- Produces: executable `scripts/test-macos-compatibility.sh` and `make test-macos-compatibility`; success prints `macOS compatibility checks passed`, mismatch exits nonzero with file-specific diagnostics.

- [ ] **Step 1: Write the failing repository contract test**

Create `scripts/test-macos-compatibility.sh` with this exact content and make it executable:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPECTED_TARGET="13.0"
FAILURES=0

fail() {
  echo "macOS compatibility check failed: $1" >&2
  FAILURES=$((FAILURES + 1))
}

check_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

check_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file is missing: $expected"
}

check_not_contains() {
  local file="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$file"; then
    fail "$file still contains unsupported declaration: $forbidden"
  fi
}

make_target="$(sed -n 's/^DEPLOYMENT_TARGET ?= //p' Makefile)"
plist_target="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Resources/Info.plist)"

check_equal "Makefile deployment target" "$make_target" "$EXPECTED_TARGET"
check_equal "Info.plist minimum system version" "$plist_target" "$EXPECTED_TARGET"
check_contains Makefile 'APPLE_SILICON_TARGET_TRIPLE ?= arm64-apple-macos$(DEPLOYMENT_TARGET)'
check_contains Makefile 'INTEL_TARGET_TRIPLE ?= x86_64-apple-macos$(DEPLOYMENT_TARGET)'
check_contains README.md '- macOS 13 或更新版本。'
check_contains README.md 'TARGET_TRIPLE="x86_64-apple-macos13.0"'
check_contains README.en.md '- macOS 13 or later.'
check_contains README.en.md 'TARGET_TRIPLE="x86_64-apple-macos13.0"'
check_contains DISTRIBUTION.md '- macOS 13 or later.'
check_contains DISTRIBUTION.md 'TARGET_TRIPLE="x86_64-apple-macos13.0"'
check_contains scripts/package-dmg.sh '- macOS 13 或更新版本。'

for file in README.md README.en.md DISTRIBUTION.md scripts/package-dmg.sh; do
  check_not_contains "$file" 'macOS 14'
  check_not_contains "$file" 'macos14.0'
done

if (( FAILURES > 0 )); then
  echo "$FAILURES macOS compatibility check(s) failed" >&2
  exit 1
fi

echo "macOS compatibility checks passed"
```

Run: `chmod +x scripts/test-macos-compatibility.sh`

- [ ] **Step 2: Run the contract to verify it fails for the current macOS 14 declarations**

Run: `./scripts/test-macos-compatibility.sh`

Expected: exit 1, including `Makefile deployment target: expected '13.0', got '14.0'`, an Info.plist mismatch, and missing macOS 13 documentation diagnostics.

- [ ] **Step 3: Lower the build and bundle minimum to macOS 13.0**

Change the Makefile source of truth to:

```make
DEPLOYMENT_TARGET ?= 13.0
```

Keep both derived triples unchanged:

```make
APPLE_SILICON_TARGET_TRIPLE ?= arm64-apple-macos$(DEPLOYMENT_TARGET)
INTEL_TARGET_TRIPLE ?= x86_64-apple-macos$(DEPLOYMENT_TARGET)
```

Change `Resources/Info.plist` to:

```xml
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
```

- [ ] **Step 4: Expose the contract through Make**

Add `test-macos-compatibility` to `.PHONY`, then add:

```make
test-macos-compatibility:
	./scripts/test-macos-compatibility.sh
```

- [ ] **Step 5: Align installation, source-build, and packaging documentation**

Make these exact substitutions:

```text
README.md:
- macOS 13 或更新版本。
TARGET_TRIPLE="x86_64-apple-macos13.0"

README.en.md:
- macOS 13 or later.
TARGET_TRIPLE="x86_64-apple-macos13.0"

DISTRIBUTION.md:
- macOS 13 or later.
make clean release TARGET_TRIPLE="x86_64-apple-macos13.0"

scripts/package-dmg.sh:
- macOS 13 或更新版本。
```

- [ ] **Step 6: Run the focused contract to verify it passes**

Run: `make test-macos-compatibility`

Expected: exit 0 and `macOS compatibility checks passed`.

- [ ] **Step 7: Validate plist and shell syntax**

Run: `plutil -lint Resources/Info.plist`

Expected: `Resources/Info.plist: OK`.

Run: `bash -n scripts/test-macos-compatibility.sh scripts/package-dmg.sh`

Expected: exit 0 with no output.

- [ ] **Step 8: Commit the compatibility contract and aligned declarations**

```bash
git add Makefile Resources/Info.plist README.md README.en.md DISTRIBUTION.md scripts/package-dmg.sh scripts/test-macos-compatibility.sh
git commit -m "feat: support macOS 13"
```

### Task 2: Gate release packaging on the compatibility contract

**Files:**
- Modify: `scripts/build-release-artifacts.sh:15-18`

**Interfaces:**
- Consumes: `make test-macos-compatibility` from Task 1.
- Produces: release packaging stops before compilation when supported-version declarations drift.

- [ ] **Step 1: Prove the contract is independently callable before wiring it in**

Run: `make test-macos-compatibility`

Expected: exit 0 and `macOS compatibility checks passed`.

- [ ] **Step 2: Add the compatibility gate to release verification**

Insert the new check before plist linting and compilation:

```bash
make test-macos-compatibility
plutil -lint Resources/Info.plist
git diff --check
```

- [ ] **Step 3: Verify release-script syntax and the focused gate**

Run: `bash -n scripts/build-release-artifacts.sh`

Expected: exit 0 with no output.

Run: `make test-macos-compatibility`

Expected: exit 0 and `macOS compatibility checks passed`.

- [ ] **Step 4: Commit the release gate**

```bash
git add scripts/build-release-artifacts.sh
git commit -m "ci: verify macOS deployment target consistency"
```

### Task 3: Verify macOS 13 runtime and both architecture targets

**Files:**
- No source files expected; do not commit generated `build/` or `dist/` artifacts.

**Interfaces:**
- Consumes: the macOS 13 configuration and compatibility gate from Tasks 1 and 2.
- Produces: exact verification evidence for the pull request body.

- [ ] **Step 1: Run repository-level static checks**

Run: `make test-macos-compatibility && git diff --check`

Expected: compatibility check passes and `git diff --check` exits 0.

- [ ] **Step 2: Run existing shell and executable self-tests**

Run these commands separately so any toolchain limitation is attributable:

```bash
./scripts/test-statistics-time-zone.sh
./scripts/test-parsers.sh
make build
build/codexU.app/Contents/MacOS/codexU --self-test-status-item
build/codexU.app/Contents/MacOS/codexU --self-test-updates
```

Expected: every runnable test exits 0. Record exact failures caused by the installed Swift compiler or SDK instead of treating them as product failures or passes.

- [ ] **Step 3: Build and inspect the Intel macOS 13 artifact**

Run:

```bash
make clean build TARGET_TRIPLE="x86_64-apple-macos13.0"
file build/codexU.app/Contents/MacOS/codexU
otool -l build/codexU.app/Contents/MacOS/codexU | sed -n '/LC_BUILD_VERSION/,/sdk/p'
/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' build/codexU.app/Contents/Info.plist
```

Expected: build exits 0; `file` reports `x86_64`; `LC_BUILD_VERSION` reports minimum OS 13.0; plist prints `13.0`.

- [ ] **Step 4: Exercise the app on the available macOS 13 Intel host**

Run:

```bash
build/codexU.app/Contents/MacOS/codexU --dump-json
```

Expected: exit 0 with a JSON object. Then launch `build/codexU.app`, confirm the main window and menu bar item appear, and quit it. Record whether macOS 13 runtime behavior was verified.

- [ ] **Step 5: Build and inspect the Apple Silicon macOS 13 artifact**

Run:

```bash
make clean build TARGET_TRIPLE="arm64-apple-macos13.0"
file build/codexU.app/Contents/MacOS/codexU
otool -l build/codexU.app/Contents/MacOS/codexU | sed -n '/LC_BUILD_VERSION/,/sdk/p'
/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' build/codexU.app/Contents/Info.plist
```

Expected when the installed SDK supports cross-compilation: build exits 0; `file` reports `arm64`; minimum OS and plist both report 13.0. Otherwise capture the exact compiler/SDK limitation for the PR.

- [ ] **Step 6: Confirm the branch contains no generated artifacts or unrelated changes**

Run:

```bash
git status --short
git diff origin/main...HEAD --stat
git log --oneline origin/main..HEAD
```

Expected: no `build/` or `dist/` files are tracked; the diff contains only the design, plan, compatibility configuration, validation script, release gate, and documentation changes.

### Task 4: Publish the community contribution

**Files:**
- No additional repository files expected.

**Interfaces:**
- Consumes: the verified `feat/macos-13-support` branch.
- Produces: a pushed branch and pull request targeting `shanggqm/codexU:main`.

- [ ] **Step 1: Review the final diff and commit state**

Run:

```bash
git diff --check
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: formatting check exits 0, worktree is clean, and commits are focused on the approved design.

- [ ] **Step 2: Push the feature branch**

Run: `git push -u origin feat/macos-13-support`

Expected: the branch is published. If direct push to upstream is denied, create or use the user's fork and push the same branch there without changing the upstream remote.

- [ ] **Step 3: Open the pull request**

Create a PR titled `Support macOS 13` targeting `shanggqm/codexU:main`. The body must include:

```markdown
## Summary

- lower the shared deployment target and bundle minimum to macOS 13.0
- align Intel and Apple Silicon packaging documentation
- add a release-time consistency check for supported-version declarations

## Verification

- `make test-macos-compatibility`
- `plutil -lint Resources/Info.plist`
- `git diff --check`
- Intel macOS 13 build and runtime: report the exact Task 3 result, including the Mach-O minimum OS when compilation succeeds
- Apple Silicon macOS 13 build: report the exact Task 3 result, including the Mach-O minimum OS when cross-compilation succeeds
- Existing self-tests: list each command that exited 0

## Notes

- no product behavior, UI, or release version changes
- if a Task 3 command was blocked by the installed compiler or SDK, quote its concise error and state that the check was not completed; omit this note only when every Task 3 check completed
```

- [ ] **Step 4: Verify the published PR**

Confirm the PR targets `main`, contains only intended commits and files, and reports verification limitations accurately. Do not claim Apple Silicon runtime testing unless it actually ran on Apple Silicon hardware.
