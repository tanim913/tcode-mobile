#!/usr/bin/env bash
# Builds the release APKs for the version in pubspec.yaml and collects them,
# named by version, in dist/vX.Y.Z/ together with SHA256SUMS.txt.
#
#   tool/build_release.sh            # both editions, arm64-v8a and armeabi-v7a
#
# Signing: release builds use the key described by ~/.tcode-release/key.properties
# (or the file named by TCODE_SIGNING). Without it they fall back to the debug
# key, and this script says so loudly, because such an APK cannot update an
# official release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION_LINE=$(grep -E '^version:' pubspec.yaml | head -1)
VERSION=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1/')
BUILD=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\2/')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || {
  echo "pubspec.yaml version must look like 1.2.3+4, found: $VERSION_LINE" >&2; exit 1; }

SIGNING=${TCODE_SIGNING:-$HOME/.tcode-release/key.properties}
if [ ! -f "$SIGNING" ]; then
  echo "WARNING: no signing key at $SIGNING — these APKs are debug-signed and" >&2
  echo "         cannot be installed over an official release." >&2
fi

OUT="dist/v$VERSION"
rm -rf "$OUT"; mkdir -p "$OUT"
APKS=build/app/outputs/flutter-apk

for FLAVOR in full play; do
  flutter build apk --release --flavor "$FLAVOR" --split-per-abi \
    --target-platform android-arm,android-arm64
  NAME=tcode-mobile; [ "$FLAVOR" = play ] && NAME=tcode-mobile-offline
  for ABI in arm64-v8a armeabi-v7a; do
    cp "$APKS/app-$ABI-$FLAVOR-release.apk" "$OUT/$NAME-v$VERSION-$ABI.apk"
  done
done

(cd "$OUT" && sha256sum ./*.apk | sed 's# \./# #' > SHA256SUMS.txt)
echo
echo "Built v$VERSION (build $BUILD) in $OUT:"
ls -lh "$OUT"
