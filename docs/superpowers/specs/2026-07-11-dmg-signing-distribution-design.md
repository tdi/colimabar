# Fix "ColimaBar is damaged" (#4) + DMG distribution cleanup

**Date:** 2026-07-11
**Issue:** https://github.com/tdi/colimabar/issues/4
**Status:** Approved

## Problem

Users who download the DMG from a GitHub release and launch the app get
"ColimaBar is damaged and can't be opened." Building from source works fine.

### Root cause (verified)

The assembled `.app` bundle is never code-signed. `swift build` emits a raw
executable that the linker gives an ad-hoc signature; that signature declares the
bundle carries sealed resources (`_CodeSignature/CodeResources`). Both
`build-app.sh` and the inline CI steps only `cp` the executable into
`ColimaBar.app/Contents/MacOS/` and drop an `Info.plist` beside it — they never
run `codesign` on the assembled bundle. So `_CodeSignature/` is absent and the
signature's claim is unsatisfied:

```
ColimaBar.app: code has no resources but signature indicates they must be present
```

An invalid signature is fatal only when Gatekeeper runs its strict assessment,
which it does for quarantined (downloaded) apps. Locally built apps carry no
`com.apple.quarantine` attribute, so the check never runs — which is why building
from source "just works." The reporter's non-admin account is unrelated.

### Fix (verified)

Re-sign the assembled bundle ad-hoc:

```
codesign --force --deep --sign - ColimaBar.app
```

This generates `_CodeSignature/CodeResources`, sealing the Info.plist and bundle.
Verified on the current bundle:

```
codesign --verify --deep --strict  ->  valid on disk
                                        satisfies its Designated Requirement
```

Ad-hoc signing needs no Apple Developer account. It does not notarize the app, so
a downloaded copy still shows the normal "unidentified developer" prompt
(clearable via right-click -> Open, or `xattr -dr com.apple.quarantine`), but it
no longer reports "damaged."

## Scope

The bug exists in two places because CI duplicates the local build scripts
inline. The design fixes it once by making the scripts the single source of truth
and having CI call them, and folds in three already-decided improvements:
universal binary, direct `.dmg` upload (no zip wrapper), and loud version
injection.

### In scope
1. Ad-hoc sign the assembled bundle (closes #4).
2. Universal binary (arm64 + x86_64) so Intel Macs work.
3. Scripts become the single source of truth; CI calls them.
4. Version injection via `PlistBuddy` (fails loud) instead of `sed`.
5. Upload `.dmg` directly; drop the zip wrapper.
6. README first-launch note + reply on issue #4.

### Out of scope
- Paid Developer ID signing and notarization.
- Homebrew cask.
- Styled DMG (background image, positioned icons).

## Components

### `build-app.sh [version]`
Single source of truth for producing a runnable `ColimaBar.app`.

- Accept optional version arg; default `0.0.0-dev`.
- `swift build -c release --arch arm64 --arch x86_64` (universal).
- Assemble bundle: create `Contents/MacOS` and `Contents/Resources`, copy the
  universal executable, copy `Sources/Info.plist` into `Contents/`.
- Set version on the **bundle's** Info.plist copy (never the source file):
  ```
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString <v>" ColimaBar.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion <v>"            ColimaBar.app/Contents/Info.plist
  ```
  `Set` on a missing key errors, so a renamed/removed key fails the build instead
  of silently shipping a mislabeled version (the failure mode of the old `sed`).
  Strip a leading `v` from the version so `v0.4` becomes `0.4`.
- `codesign --force --deep --sign - ColimaBar.app`.
- Verify: `codesign --verify --deep --strict ColimaBar.app` — fail the build if
  the bundle is not valid.

### `build-dmg.sh [version]`
- Accept optional version arg; default `0.0.0-dev`.
- Always call `./build-app.sh "$version"` (drop the "skip if bundle exists"
  shortcut — stale bundles are a footgun in CI).
- Output name: `ColimaBar-<version>.dmg`.
- Plain `hdiutil`: temp dir with the app bundle plus a `/Applications` symlink,
  `hdiutil create -format UDZO`.
- Print final path and size.

### `.github/workflows/release.yml`
Collapses to:

1. Checkout.
2. Derive `VERSION` from `github.ref_name`.
3. `./build-dmg.sh "$VERSION"`.
4. Upload `ColimaBar-<VERSION>.dmg` via `softprops/action-gh-release`.

Removed: inline `swift build`, inline bundle assembly, the `sed` version hack, the
DMG-in-zip step. Version handling now lives entirely in `build-app.sh`.

## Data flow

```
git tag vX.Y  ->  push
             ->  release.yml: VERSION=vX.Y
             ->  build-dmg.sh vX.Y
                   -> build-app.sh vX.Y
                        -> swift build (universal)
                        -> assemble bundle
                        -> PlistBuddy set version (X.Y)
                        -> codesign --force --deep --sign -
                        -> codesign --verify (gate)
                   -> hdiutil create ColimaBar-vX.Y.dmg
             ->  upload ColimaBar-vX.Y.dmg to the release
```

## Error handling

- `set -e` in both scripts (already present).
- `codesign --verify` after signing is a hard gate: a bundle that does not
  validate must not reach a DMG. This is the specific regression guard for #4.
- `PlistBuddy Set` on a missing key exits non-zero, failing the build.

## Testing / verification

Before shipping, reproduce the download condition locally:

1. `./build-dmg.sh v0.4-test`
2. Mount the DMG, copy `ColimaBar.app` out.
3. `xattr -w com.apple.quarantine "0081;00000000;Safari;" ColimaBar.app` on the
   copy to simulate a downloaded app.
4. `spctl -a -t exec -vvv ColimaBar.app` — expect "rejected (unidentified
   developer)", NOT "damaged" / "no resources".
5. `lipo -archs ColimaBar.app/Contents/MacOS/ColimaBar` — expect `x86_64 arm64`.

Success = the "damaged" / "no resources" failure is gone and both archs are
present.

## Follow-up (not code)

- README: short "first launch" note — right-click -> Open, or
  `xattr -dr com.apple.quarantine /Applications/ColimaBar.app`.
- Reply on issue #4 with the workaround for the current v0.3 download and note
  the next tagged release fixes it at the source.
