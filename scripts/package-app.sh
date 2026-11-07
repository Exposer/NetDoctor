#!/bin/bash
# Build NetDoctor.app (universal by default), sign it ad hoc, verify it, and zip it into dist/.
#
#   scripts/package-app.sh                # universal (Intel + Apple silicon) -> dist/NetDoctor-<version>-macOS-universal.zip
#   UNIVERSAL=0 scripts/package-app.sh    # this Mac's architecture only (faster)
#
# Why a script and not just NetDoctorApp/build-app.sh: the app is built in a temporary folder OUTSIDE the
# repository. In an iCloud-synced folder (~/Documents, ~/Desktop) the system keeps adding
# com.apple.FinderInfo to the bundle and codesign then refuses to sign it. The result is verified after
# zipping and again after unzipping, so a broken signature fails here instead of on a user's Mac.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=$(sed -n 's/^VERSION=//p' "$ROOT/netdoctor" | head -1)
[ -n "$VER" ] || { echo "VERSION not found in netdoctor" >&2; exit 1; }
UNIVERSAL=${UNIVERSAL:-1}
KIND=universal; [ "$UNIVERSAL" = 1 ] || KIND=$(uname -m)

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/NetDoctorApp"
cp -R "$ROOT/assets" "$ROOT/netdoctor" "$WORK/"
cp -R "$ROOT/NetDoctorApp/Package.swift" "$ROOT/NetDoctorApp/Sources" "$ROOT/NetDoctorApp/Tests" "$ROOT/NetDoctorApp/Resources" \
      "$ROOT/NetDoctorApp/build-app.sh" "$WORK/NetDoctorApp/"   # Tests: Package.swift declares the test target, so its folder must exist

echo "== building NetDoctor $VER ($KIND)"
( cd "$WORK/NetDoctorApp" && UNIVERSAL=$UNIVERSAL ./build-app.sh )
APP="$WORK/NetDoctorApp/NetDoctor.app"

echo "== verifying the bundle"
xattr -cr "$APP"
codesign --force --deep -s - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
BUNDLE_VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$BUNDLE_VER" = "$VER" ] || { echo "bundle version $BUNDLE_VER does not match VERSION $VER" >&2; exit 1; }
ARCHS=$(lipo -archs "$APP/Contents/MacOS/NetDoctor")
if [ "$UNIVERSAL" = 1 ]; then
  case "$ARCHS" in *arm64*x86_64*|*x86_64*arm64*) ;; *) echo "expected a universal binary, got: $ARCHS" >&2; exit 1;; esac
fi
BUNDLED_CLI=$("$APP/Contents/Resources/netdoctor" version)
[ "$BUNDLED_CLI" = "netdoctor $VER" ] || { echo "bundled CLI says '$BUNDLED_CLI'" >&2; exit 1; }

echo "== zipping"
mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/NetDoctor-$VER-macOS-$KIND.zip"
rm -f "$ZIP"
ditto -c -k --keepParent --noextattr --norsrc "$APP" "$ZIP"

echo "== verifying the zip"
mkdir "$WORK/unzip"; ditto -x -k "$ZIP" "$WORK/unzip"
codesign --verify --deep --strict "$WORK/unzip/NetDoctor.app"

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo
echo "built:   $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "archs:   $ARCHS"
echo "version: $VER"
echo "sha256:  $SHA"
