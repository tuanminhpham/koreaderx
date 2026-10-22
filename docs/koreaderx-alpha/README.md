# KOReaderX Test Alpha 1.0

This is a source milestone, not a renamed APK or a new release. The APK identity in artifact.json is unchanged.

## Verified source

The installed Test APK was read from ONYX TabXC on 2026-10-22. Its SHA256 equals the retained S11 artifact. All 490 checked packaged frontend/plugin files and launcher android.lua match source commit `b74df73f87786442d73429815c27b771457be000`. Build receipts identify the actual build checkout as `upgrade-runs/v2026.07.1-ZWSqRJ0v/apk-build`, populated from `implementation`. Both existing checkouts now contain three later full-access-only commits ending at `573fdb76b378a8989e19254b959c1555715cf77e`; those commits remain untouched and are excluded here. A new independent checkout was used to preserve them. No uncommitted implementation changes were found.

This snapshot adds only build/handoff documentation, scripts and a fetchable launcher submodule URL. Runtime source and gitlinks equal the verified APK source. No new assistant plugin integration belongs to Alpha.

Dependencies:
- base: `fa81dbb114fdd623f0b8e9d1d6b56f6321265998`, https://github.com/tuanminhpham/koreader-base branch `koreaderx/alpha-1.0`.
- launcher: `d7cd36784e0b5f32e56541d14248ee172cd7af04`, hosted as dependency history at https://github.com/tuanminhpham/koreaderx branch `koreaderx/alpha-1.0-launcher`. The .gitmodules URL deliberately uses this existing repository; the pinned gitlink selects launcher history, not the repository's default branch.
- crengine: `b32a88ffbbf505cf2ea5208c1a49002d70d3609f`, upstream koreader/crengine.
- l10n: `be4726d0fa58195dbe6f2b868ddafd2b18e472d9`.
- fonts: `046976988aa33639d60d6ffd25c7a0ff50b72ac0`.
- test-data: `c3b5d06e1ae8ea088bd898b0e7f9da3753d0d86c`.

## Build

Clone branch `koreaderx/alpha-1.0` recursively, or checkout annotated tag `v1.0.0-alpha.1` and run `git submodule update --init --recursive`.
Build the container from `tools/koreaderx/Dockerfile`. Its base is pinned by digest. The local reference image is `sha256:e5ad2f0c062427c8d6141331b782bbbbb586646897e8a2ab743ce090cf395e3a`. Toolchain: Android NDK r23c (23.2.8568313), JDK17, Gradle8.6, AGP8.4.2, Kotlin1.9.24; compile/target SDK30, minSDK18, ARM64 API21 native target. Inspection uses Android build-tools34.0.0. The Dockerfile apt layer is not a bit-for-bit reproducibility guarantee.

Mount the checkout read-write at /work, use /work as working directory, and set ANDROID_HOME=/opt/android-sdk-linux, ANDROID_NDK_HOME=/opt/android-ndk-r23c, GRADLE_USER_HOME to a persistent cache, PARALLEL_JOBS=6, JAVA_TOOL_OPTIONS=-Duser.home=/private-java-home. Supply the existing companion debug signing keystore privately at /private-java-home/.android/debug.keystore. Do not commit that key, device profiles, credentials or API keys. Verify the public signing certificate fingerprint against artifact.json BEFORE installing an update. A newly auto-generated debug key will not update the existing app. This snapshot does not distribute the private signing key.

Run inside that container:

```sh
ANDROID_VERSION=11966 \
ANDROID_NAME=v2026.07.1-KOReaderX-S11-b74df73f8778 \
KX_OUTPUT_DIR=/output bash tools/koreaderx/build-test.sh
```

These overrides preserve the historical APK's Android version identity. An exact historical source rebuild should use a separate checkout at b74df73f8778 (copy the helper into it), fetching the pinned launcher revision from the dependency branch before submodule checkout. Additional tags can change git describe/module version; preserve original artifacts for byte-level comparison. Do not claim rebuilt APK SHA equality without measuring it. Later development must increase ANDROID_VERSION for updates. The script never installs or uninstalls. For an update use only `adb -s SERIAL install -r VERIFIED.apk` after backup and package/certificate verification; avoid kodev run/make run because Android run targets can uninstall.

## Data and features

Package: org.koreader.launcher.koreaderxtest. Private profile: /data/user/0/org.koreader.launcher.koreaderxtest/app_koreaderx-test (Context.getDir; verified alias /data/data). Test books are limited to /storage/emulated/0/Books/test/KOReaderX_S10_ZWSqRJ0v. Keep real books and the separate full-access app untouched.

Implemented: exact PDF annotation provenance and import handling; saved highlight overlay fixes; compact 13-button toolbar; PDF Fit full/Page defaults with user choices retained; automatic single toolbar after ReaderReady; footer-aware placement and scaling; persistent reader TOC panel with immediate background page updates, rotation and consumed outside-dismiss tap.

## Evidence and open issues

Historical S11 host: 55 tests across six groups passed, final affected groups rerun passed, Lua lint clean. Nine core UI flows passed on installed APK119662: automatic toolbar/footer, Fit full/Page, portrait/landscape geometry, successive TOC60→76→94 and rotation→120, outside dismissal, repeated open/rotation, reopen/restart, highlight navigation and extracurriculars selection, persistence of user Fit width. Extra device DPI480 and footer Height14→24→14 passed and original settings restored. On 2026-10-22, installed APK hash/source/signature were reverified; historical UI results are not presented as new runs.

Open: hierarchical TOC branches have host coverage only; provided PDF TOCs are flat. JNI SIGABRT in File manager existed before S11, root cause unconfirmed. Intrinsic PDF Rotate90 can select a line instead of one word; reflow hold overlay can cover only part of a word; ordinary multi-page highlight endpoint shrinking remains problematic. Old annotation provenance/migration and full rollback compatibility need further evidence. Existing plugins lack complete offline/service acceptance. No external assistant service result is claimed. This is an alpha with known limitations, not full product acceptance.

Detailed local reports: koreader/toolbar-development/report.html, toolbar-development/checkpoint.json, and upgrade-runs/v2026.07.1-ZWSqRJ0v/RESUME.md. Personal screenshots/profiles and copyrighted PDF fixtures are deliberately not published.
