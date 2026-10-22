# Building the assistant integration

The post-Alpha-1 integration is included in `plugins/assistant.koplugin`. A fresh clone builds this vendored snapshot; it does not require a developer's `$HOME/Projects/koreaderx/assistant.koplugin` directory. File hashes are recorded in `tools/koreaderx/assistant-files.json`.

## Build from a published source snapshot

Clone the intended branch/tag recursively, or run `git submodule update --init --recursive` after checking it out. Use `tools/koreaderx/Dockerfile` and the toolchain/signing setup documented in `docs/koreaderx-alpha/README.md`. Dependency downloads require network access unless caches are populated. The pinned base image and source revisions do not guarantee a byte-identical rebuild: version overrides, dependency downloads and signing material also affect it.

From the checkout root, validate the vendored source first:

```sh
python3 tools/koreaderx/sync-assistant.py --check
# --check is also the default when --source is omitted.
```

Inside the documented Android toolchain container, with the checkout mounted at `/work` and an output directory at `/output`:

```sh
cd /work
# No external assistant source is required for a release build.
env -u ASSISTANT_SOURCE \
  ANDROID_VERSION=11974 \
  ANDROID_NAME=v2.0.0-alpha.1-KOReaderX-Test \
  KX_OUTPUT_DIR=/output \
  bash tools/koreaderx/build-test.sh
```

These overrides specify Alpha 2.0. Pipeline input `11974` produces ARM64 Android versionCode `119742`; verify the actual APK against BUILD_INFO.json. Increase the version for a later update. The script validates the plugin manifest before regenerating assets with `kodev release -i android-arm64`, then runs `assembleArm64RocksDebug` with `isolatedTest=true`. It never installs or uninstalls an app.

Supply the existing Test signing key privately to produce a compatible update. Its public certificate SHA256 is `4ced17eb89f07fe72eec6e5768b9d5e0720683224c0d491e3693c8f54d3d535d`. A newly generated debug key produces a different signer. Never commit a signing key, API key or device profile. Check the APK's package, ABI, version and certificate before installation; preserve data with `adb -s SERIAL install -r VERIFIED.apk`, never uninstall/clear-data or `kodev run`.

Validation is read-only: missing/mismatched files, unexpected packaged files (including personal configuration.lua), symlinks and recognizable credentials fail the build. Literal `api_key` assignments may contain only empty values, `your-...` placeholders or the documented `ollama` sentinel. This scan is a guard, not proof that arbitrary source contains no secret; review the diff before publishing.

## Explicit development sync

The editable development source may remain outside the repository. Sync it only when intentionally importing changes:

```sh
cd /path/to/checkout
python3 tools/koreaderx/sync-assistant.py \
  --source "$HOME/Projects/koreaderx/assistant.koplugin"
python3 tools/koreaderx/sync-assistant.py --check
git diff -- plugins/assistant.koplugin tools/koreaderx/assistant-files.json
```

A changed destination is backed up in `/tmp/koreaderx-assistant-backups` before replacement. The allowlist copies entry points, assistant modules, API handlers, safe default/sample config, translations and documentation/license. It excludes personal `configuration.lua`, caches, development files and native binaries. Review and commit the synchronized files and manifest before creating a release snapshot.

For development builds, explicitly set `ASSISTANT_SOURCE=/assistant-source` and mount that directory read-only in the container. An unset or empty variable uses only the vendored source. Workspace-specific wrappers that export it must unset it for release builds; they are not a dependency of the published repository.

## Runtime data and verification

Resources resolve relative to `assistant_paths.lua`. Writable provider configuration is `settings/assistant-configuration.lua` in the active profile; UI choices are separate in `settings/assistant.lua`. The Test Android profile is `/data/user/0/org.koreader.launcher.koreaderxtest/app_koreaderx-test`. No production/shared profile config is imported automatically. Without private configuration the provider is offline: local UI works, and a query reports that no request was sent.

HTTPS requests use packaged `data/ca-bundle.crt`, peer certificate validation and SAN hostname checks before headers or text are sent. HTTPS redirects are disabled for assistant requests. Legacy CN-only certificates and mismatched IPv6 spellings fail closed. Global KOReader HTTPS settings are unchanged. The optional hoedown library is absent; Markdown uses the included Lua parser.

Run the transport test using an existing KOReader host runtime containing LuaJIT and LuaSec1.3.2:

```sh
python3 tools/koreaderx/test-assistant-tls.py --runtime /path/to/host-runtime
```

This creates temporary certificates and loopback TLS servers, testing10 requests across both API paths plus13 SAN cases. No provider or API key is used. UI integration tests are in `spec/unit/koreaderx_assistant_spec.lua`; use the normal host test harness and isolated fixtures. Host tests do not replace device UI acceptance. The verified119722 device run demonstrated Gemini translation in nonstream mode; Mistral returned429 twice and was stopped. Streaming generation and other providers were not accepted by that run.

The Makefile selects upstream calendar-version tags for the runtime Git revision because KOReader's version parser cannot parse Alpha milestone names. APK manifest versionName/versionCode and Git milestones are separate identities; retain verified APKs and inspection receipts.
