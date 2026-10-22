#!/usr/bin/env bash
# Run inside the documented Android toolchain container from the checkout root.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
: "${ANDROID_VERSION:=$(git rev-list --count HEAD)}"
: "${ANDROID_NAME:=v2026.07.1-KOReaderX-Test-$(git rev-parse --short=12 HEAD)}"
export ANDROID_VERSION ANDROID_NAME
OUT=${KX_OUTPUT_DIR:-/tmp/koreaderx-test-build}
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
# A fresh clone builds its vendored snapshot. External development sync is opt-in.
if [[ -n "${ASSISTANT_SOURCE:-}" ]]; then
    python3 tools/koreaderx/sync-assistant.py --source "$ASSISTANT_SOURCE" --checkout "$ROOT"
fi
python3 tools/koreaderx/sync-assistant.py --check --checkout "$ROOT"
# This prepares the optimized native libraries AND regenerates the resource archive.
./kodev release -i android-arm64
STAGE="$ROOT/koreader-android-aarch64-unknown-linux-android21/luajit-launcher"
LAUNCHER="$ROOT/platform/android/luajit-launcher"
"$LAUNCHER/gradlew" --project-dir="$LAUNCHER" --project-cache-dir="$OUT/gradle-cache"  -PassetsPath="$STAGE/assets" -PlibsPath="$STAGE/libs" -PbuildDir="$OUT/gradle-build"  -PsevenZipLib=koreader-monolibtic '-PprojectName=KOReaderX Test'  -PversCode="$ANDROID_VERSION" -PversName="$ANDROID_NAME" -PisolatedTest=true  --console=plain --no-daemon --max-workers=6 app:assembleArm64RocksDebug
cp "$OUT/gradle-build/outputs/apk/arm64Rocks/debug/NativeActivity.apk" "$OUT/KOReaderX-Test-$ANDROID_NAME.apk"
sha256sum "$OUT/KOReaderX-Test-$ANDROID_NAME.apk"
