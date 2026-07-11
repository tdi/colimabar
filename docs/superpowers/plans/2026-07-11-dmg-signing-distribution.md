# Fix Damaged-App DMG Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop downloaded ColimaBar DMGs from failing Gatekeeper with "is damaged" by ad-hoc signing the assembled app bundle, and ship a universal binary from deduplicated build scripts.

**Architecture:** `build-app.sh` becomes the single source of truth: universal `swift build`, bundle assembly, version injection via PlistBuddy, ad-hoc `codesign`, and a `codesign --verify` gate. `build-dmg.sh` calls it and packages a `.dmg`. `release.yml` collapses to calling `build-dmg.sh` and uploading the `.dmg`. There is no unit-test harness — verification is real-build assertions (`codesign --verify`, `lipo`, `spctl`).

**Tech Stack:** Bash, Swift Package Manager, `codesign`, `hdiutil`, `/usr/libexec/PlistBuddy`, GitHub Actions.

## Global Constraints

- Ad-hoc signing only (`codesign --sign -`) — no Apple Developer account, no notarization.
- Universal binary required: `swift build -c release --arch arm64 --arch x86_64`.
- Version arg default: `0.0.0-dev`. Strip a leading `v` before writing to Info.plist; keep the raw arg (with `v`) in the DMG filename.
- Never mutate `Sources/Info.plist`; only edit the copy inside the assembled bundle.
- `set -e` in every script. The `codesign --verify --deep --strict` check is a hard build gate.
- App name `ColimaBar`; bundle `ColimaBar.app`; DMG `ColimaBar-<version>.dmg`.
- No emojis, no TODO/placeholder comments in shipped files.

---

### Task 1: Rewrite `build-app.sh` — universal build, PlistBuddy version, ad-hoc sign, verify gate

**Files:**
- Modify: `build-app.sh` (full rewrite)
- Reference (do not edit): `Sources/Info.plist`, `Package.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `./build-app.sh [version]` → a valid, ad-hoc-signed, universal `ColimaBar.app` in the repo root. Default version `0.0.0-dev`. Exits non-zero if the bundle does not codesign-verify. Later tasks (`build-dmg.sh`) call this with the version string.

- [ ] **Step 1: Write the new `build-app.sh`**

Replace the entire contents of `build-app.sh` with:

```bash
#!/bin/bash
set -e

APP_NAME="ColimaBar"
BUILD_DIR=".build/apple/Products/Release"
APP_BUNDLE="$APP_NAME.app"

# Version: strip a leading "v" for Info.plist (v0.4 -> 0.4). Default dev value.
RAW_VERSION="${1:-0.0.0-dev}"
VERSION="${RAW_VERSION#v}"

echo "Building $APP_NAME $VERSION (universal)..."
swift build -c release --arch arm64 --arch x86_64

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "Sources/Info.plist" "$APP_BUNDLE/Contents/"

# Set version on the bundle's Info.plist copy. `Set` errors on a missing key,
# so a renamed/removed key fails the build instead of silently shipping wrong.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign the assembled bundle. This generates _CodeSignature/CodeResources,
# which the linker's ad-hoc signature on the raw binary requires. Without it a
# downloaded (quarantined) app fails Gatekeeper as "damaged" (issue #4).
echo "Signing bundle (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Hard gate: a bundle that does not validate must not reach a DMG.
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "App bundle created and signed at $APP_BUNDLE"
```

Note: `swift build --arch arm64 --arch x86_64` emits the universal binary under
`.build/apple/Products/Release/`, not `.build/release/`. The path change is
required — do not keep `.build/release`.

- [ ] **Step 2: Run it and verify it produces a valid universal bundle**

```bash
./build-app.sh v0.4-test
```

Expected: ends with "Verifying signature..." then codesign printing
`valid on disk` and `satisfies its Designated Requirement`, exit 0.

- [ ] **Step 3: Assert the two invariants that fix #4**

```bash
lipo -archs ColimaBar.app/Contents/MacOS/ColimaBar
codesign --verify --deep --strict ColimaBar.app && echo "VERIFY_OK"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" ColimaBar.app/Contents/Info.plist
```

Expected:
- `lipo` prints `x86_64 arm64` (order may vary).
- prints `VERIFY_OK`.
- version prints `0.4-test` (leading `v` stripped).

- [ ] **Step 4: Confirm the source Info.plist was not mutated**

```bash
git diff --quiet Sources/Info.plist && echo "SOURCE_UNCHANGED"
```

Expected: prints `SOURCE_UNCHANGED`.

- [ ] **Step 5: Commit**

```bash
git add build-app.sh
git commit -m "Sign app bundle ad-hoc and build universal binary

The assembled bundle was never codesigned, so the linker's ad-hoc
signature claimed sealed resources that did not exist; downloaded
(quarantined) copies failed Gatekeeper as damaged (#4). Sign the
assembled bundle, verify it, and build a universal (arm64+x86_64)
binary. Version now set via PlistBuddy, which fails loud on a missing
key."
```

---

### Task 2: Rewrite `build-dmg.sh` — always rebuild, versioned output name

**Files:**
- Modify: `build-dmg.sh` (full rewrite)

**Interfaces:**
- Consumes: `./build-app.sh [version]` from Task 1.
- Produces: `./build-dmg.sh [version]` → `ColimaBar-<version>.dmg` in the repo root, where `<version>` is the raw arg (leading `v` preserved). Default `0.0.0-dev`.

- [ ] **Step 1: Write the new `build-dmg.sh`**

Replace the entire contents of `build-dmg.sh` with:

```bash
#!/bin/bash
set -e

APP_NAME="ColimaBar"
VOLUME_NAME="$APP_NAME"
APP_BUNDLE="$APP_NAME.app"

RAW_VERSION="${1:-0.0.0-dev}"
DMG_NAME="$APP_NAME-$RAW_VERSION.dmg"

# Always rebuild the bundle so the DMG can never contain a stale app.
echo "Building app bundle..."
./build-app.sh "$RAW_VERSION"

echo "Creating DMG $DMG_NAME..."
rm -f "$DMG_NAME"

DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_NAME"

rm -rf "$DMG_TEMP"

echo ""
echo "DMG created: $DMG_NAME"
echo "Size: $(du -h "$DMG_NAME" | cut -f1)"
```

- [ ] **Step 2: Run it**

```bash
./build-dmg.sh v0.4-test
```

Expected: builds the app, then prints `DMG created: ColimaBar-v0.4-test.dmg`
and a size line. Exit 0.

- [ ] **Step 3: Verify the DMG exists and the app inside it is valid when quarantined**

```bash
test -f ColimaBar-v0.4-test.dmg && echo "DMG_EXISTS"
MNT=$(hdiutil attach ColimaBar-v0.4-test.dmg -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
cp -R "$MNT/ColimaBar.app" /tmp/ColimaBar-q.app
hdiutil detach "$MNT" >/dev/null
xattr -w com.apple.quarantine "0081;00000000;Test;" /tmp/ColimaBar-q.app
spctl -a -t exec -vvv /tmp/ColimaBar-q.app 2>&1 | grep -v "no resources" && echo "NOT_DAMAGED"
rm -rf /tmp/ColimaBar-q.app
```

Expected: prints `DMG_EXISTS`. `spctl` reports `rejected` with source
`unidentified developer` (NOT "no resources"/"damaged"), then prints
`NOT_DAMAGED`. This is the direct regression check for issue #4.

- [ ] **Step 4: Clean up test artifacts**

```bash
rm -f ColimaBar-v0.4-test.dmg
```

Expected: no output, exit 0. (`ColimaBar.app` and `*.dmg` are gitignored.)

- [ ] **Step 5: Commit**

```bash
git add build-dmg.sh
git commit -m "Version DMG name and always rebuild the bundle

DMG output is now ColimaBar-<version>.dmg and always rebuilds via
build-app.sh so it can never package a stale unsigned bundle."
```

---

### Task 3: Simplify `release.yml` to call the scripts and upload the DMG

**Files:**
- Modify: `.github/workflows/release.yml` (full rewrite)

**Interfaces:**
- Consumes: `./build-dmg.sh "$VERSION"` from Task 2, which yields `ColimaBar-<VERSION>.dmg`.
- Produces: a GitHub release with `ColimaBar-<VERSION>.dmg` attached, on `v*` tag push.

- [ ] **Step 1: Write the new workflow**

Replace the entire contents of `.github/workflows/release.yml` with:

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build DMG
        env:
          VERSION: ${{ github.ref_name }}
        run: ./build-dmg.sh "$VERSION"

      - name: Upload Release Assets
        uses: softprops/action-gh-release@v1
        with:
          files: ColimaBar-${{ github.ref_name }}.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Removed from the old workflow: inline `swift build`, inline bundle assembly,
the `sed` version hack, and the DMG-in-zip step. Version handling and signing
now live entirely in the scripts.

- [ ] **Step 2: Verify the scripts are executable (so CI can call them directly)**

```bash
test -x build-app.sh && test -x build-dmg.sh && echo "EXECUTABLE"
```

Expected: prints `EXECUTABLE`. If not:
`chmod +x build-app.sh build-dmg.sh && git add build-app.sh build-dmg.sh`.

- [ ] **Step 3: Lint the workflow YAML**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML_OK')"
```

Expected: prints `YAML_OK`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "Drive release workflow through build scripts

CI no longer duplicates the build inline (which is how the missing
codesign step reached releases). It now calls build-dmg.sh and uploads
the .dmg directly, dropping the zip wrapper."
```

---

### Task 4: README first-launch note

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: user-facing install instructions covering the ad-hoc-signed first launch.

- [ ] **Step 1: Locate the install section**

```bash
grep -n -i "install\|dmg\|download\|## " README.md
```

Expected: prints the heading lines. Note the install/download heading's line
number for the next step.

- [ ] **Step 2: Add a first-launch note under the install instructions**

Insert this block immediately after the DMG install steps (drag-to-Applications).
Match the surrounding heading level; if install steps sit under a `##` heading,
use `###` here:

```markdown
### First launch

ColimaBar is ad-hoc signed, not notarized by Apple, so on first launch macOS
shows an "unidentified developer" warning. Right-click the app in Applications
and choose **Open**, then confirm. You only need to do this once.

If macOS still refuses to open it, clear the download quarantine flag:

```
xattr -dr com.apple.quarantine /Applications/ColimaBar.app
```
```

- [ ] **Step 3: Verify it renders and reads correctly**

```bash
grep -n "First launch" README.md && grep -n "com.apple.quarantine" README.md
```

Expected: both lines print with line numbers.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Document ad-hoc first-launch step in README"
```

---

### Task 5: Manual release + issue #4 reply (human-run checklist)

**Files:** none (operational steps).

**Interfaces:**
- Consumes: merged Tasks 1-4 on `main`.
- Produces: a tagged release whose DMG opens without "damaged", and a closing reply on issue #4.

- [ ] **Step 1: Tag and push a release** (run by the maintainer once changes are on `main`)

```bash
git tag v0.4
git push origin v0.4
```

Expected: the "Build and Release" workflow runs and attaches
`ColimaBar-v0.4.dmg` to the v0.4 release.

- [ ] **Step 2: Confirm CI succeeded and the asset is the DMG (not a zip)**

```bash
gh run list --limit 1
gh release view v0.4 --json assets --jq '.assets[].name'
```

Expected: run status `success`; asset name `ColimaBar-v0.4.dmg`.

- [ ] **Step 3: Download the released DMG and confirm it is not "damaged"**

```bash
cd "$(mktemp -d)"
gh release download v0.4 --pattern '*.dmg'
MNT=$(hdiutil attach ColimaBar-v0.4.dmg -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
codesign --verify --deep --strict --verbose=2 "$MNT/ColimaBar.app" && echo "RELEASED_DMG_VALID"
hdiutil detach "$MNT" >/dev/null
```

Expected: prints `RELEASED_DMG_VALID`. (The downloaded DMG carries real
quarantine, so this exercises the exact condition from the bug report.)

- [ ] **Step 4: Reply on issue #4 and close it**

```bash
gh issue comment 4 --body "Fixed in v0.4. The DMG's app bundle was never codesigned, so downloaded copies failed Gatekeeper as \"damaged\" (local builds are not quarantined, which is why source builds worked). v0.4 ships an ad-hoc-signed universal build.

On first launch, right-click the app and choose Open (it is signed ad-hoc, not notarized). If you are still on an older download, you can clear the quarantine flag manually:

    xattr -dr com.apple.quarantine /Applications/ColimaBar.app

Thanks for the clear report."
gh issue close 4
```

Expected: comment posts and the issue closes.

---

## Self-Review

**Spec coverage:**
- Ad-hoc sign bundle (closes #4) → Task 1, Steps 1-3; regression-checked in Task 2 Step 3 and Task 5 Step 3.
- Universal binary → Task 1 (`--arch arm64 --arch x86_64`, `lipo` assert).
- Scripts as single source of truth; CI calls them → Tasks 1-2 own the logic, Task 3 reduces CI to a call.
- PlistBuddy version injection, fail loud → Task 1 Step 1 + assert Step 3.
- Direct `.dmg` upload, drop zip → Task 3 Step 1.
- README first-launch note → Task 4.
- Issue #4 reply → Task 5 Step 4.
- Verification/quarantine simulation from spec → Task 2 Step 3 (local) and Task 5 Step 3 (real download).

**Placeholder scan:** No TBD/TODO; every code step shows full file contents or exact commands.

**Type/name consistency:** `RAW_VERSION`/`VERSION` split consistent across Tasks 1-2; DMG name `ColimaBar-<RAW_VERSION>.dmg` consistent in Tasks 2, 3, 5; build output path `.build/apple/Products/Release` used only in Task 1. Verify gate command identical in Tasks 1, 5.

**Known environment note:** the universal build output path (`.build/apple/Products/Release/`) differs from the old single-arch path (`.build/release/`). Task 1 Step 2 will surface a copy error immediately if this path is wrong on the runner's toolchain; if so, locate the binary with `swift build -c release --arch arm64 --arch x86_64 --show-bin-path` and update `BUILD_DIR`.
