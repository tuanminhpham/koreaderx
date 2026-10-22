# Build KOReaderX Test Alpha 2.0

This source snapshot includes the distributable Assistant plugin. It does not need the developer's external plugin directory or private provider configuration.

```sh
git clone --recurse-submodules --branch v2.0.0-alpha.1 \
  https://github.com/tuanminhpham/koreaderx.git koreaderx-alpha2
cd koreaderx-alpha2
python3 tools/koreaderx/sync-assistant.py --check
docker build -t koreaderx-alpha2-tools -f tools/koreaderx/Dockerfile .
```

The Dockerfile pins `koreader/koandroid` by digest. The reference build used Android NDK r23c, JDK17, Gradle8.6, Android Gradle Plugin8.4.2, Kotlin1.9.24 and Android build-tools34.0.0 for inspection. The app's compile/target SDK is30 and minSDK is18; the ARM64 native target is API21. The apt layer, caches and signatures mean this is not a claim of bit-for-bit reproducibility.

Supply the existing Test signing key privately when rebuilding an update. The required public certificate SHA256 is `4ced17eb89f07fe72eec6e5768b9d5e0720683224c0d491e3693c8f54d3d535d`. The private key is not distributed. A new auto-generated debug key cannot update the installed Test app; do not uninstall to work around that mismatch.

Choose external cache/output directories and a private Java home containing `.android/debug.keystore`. Keep all three outside the Git checkout. For example, after setting `KX_CACHE`, `KX_OUTPUT` and `KX_SIGNER_HOME` to your own absolute paths:

```sh
mkdir -p "$KX_CACHE" "$KX_OUTPUT"
docker run --rm --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$PWD,dst=/work" \
  --mount "type=bind,src=$KX_OUTPUT,dst=/output" \
  --mount "type=bind,src=$KX_CACHE,dst=/cache" \
  --mount "type=bind,src=$KX_SIGNER_HOME,dst=/private-java-home,readonly" \
  --workdir /work \
  --env ANDROID_HOME=/opt/android-sdk-linux \
  --env ANDROID_NDK_HOME=/opt/android-ndk-r23c \
  --env GRADLE_USER_HOME=/cache/gradle \
  --env CCACHE_DIR=/cache/ccache --env XDG_CACHE_HOME=/cache/xdg \
  --env JAVA_TOOL_OPTIONS=-Duser.home=/private-java-home \
  --env PARALLEL_JOBS=6 \
  --env ANDROID_VERSION=11974 \
  --env ANDROID_NAME=v2.0.0-alpha.1-KOReaderX-Test \
  --env KX_OUTPUT_DIR=/output \
  --entrypoint /bin/bash koreaderx-alpha2-tools \
  -c 'env -u ASSISTANT_SOURCE bash tools/koreaderx/build-test.sh'
```

`build-test.sh` validates the73-file vendored plugin manifest, regenerates Android assets with `kodev release -i android-arm64`, then runs `app:assembleArm64RocksDebug`. This is a **debuggable Android APK with optimized native libraries**, not a production-signed Release variant. The launcher derives ARM64 versionCode **119742** from input11974; inspect the actual APK rather than inferring its manifest identity from the input alone. Rename the output APK to `KOReaderX-Test-Alpha-2.0-arm64-v8a.apk` only after verifying package, version, ABI and signer.

If the external plugin source changes during development, explicitly sync it first using `--source`, review and commit the resulting plugin/manifest changes, and only then freeze and build the release. See [the Assistant build notes](koreaderx-assistant.md). An unset `ASSISTANT_SOURCE` builds solely from the committed snapshot.

The release's `BUILD_INFO.json`, `SOURCE_MANIFEST.json`, `TEST_RESULTS.json` and `SHA256SUMS.txt` record the final artifact and verification scope. Check source/plugin/launcher payloads against the frozen commit, verify the APK signature, and calculate checksums after all assets are final. No build target here installs or removes an app. For a verified update, back up first and use only `adb -s SERIAL install -r VERIFIED.apk`; avoid `kodev run`/`make run`, whose Android targets may uninstall.
