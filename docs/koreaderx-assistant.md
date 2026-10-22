# Assistant integration after Alpha 1.0

Development base: annotated v1.0.0-alpha.1 / 8f27a80e7302560d2034f603d213493b96ac9a10, verified by fresh recursive GitHub clone before integration. These changes remain local.

Authoritative editable source: $HOME/Projects/koreaderx/assistant.koplugin. It was an unversioned plugin1.09 directory; a private local tar backup was retained before edits. The tracked plugins/assistant.koplugin snapshot contains only distributable sources/resources, with SHA256 per file in tools/koreaderx/assistant-files.json. Never add the source configuration.lua or backup to Git.

```sh
python3 tools/koreaderx/sync-assistant.py --source "$HOME/Projects/koreaderx/assistant.koplugin"
# In the Alpha toolchain container, mount source read-only and set its container path:
ASSISTANT_SOURCE=/assistant-source ANDROID_VERSION=11970 \
ANDROID_NAME=v2026.07.1-KOReaderX-Assistant-COMMIT \
KX_OUTPUT_DIR=/output bash tools/koreaderx/build-test.sh
```

Build-test always synchronizes before regenerating assets. Sync preserves an existing different destination in /tmp/koreaderx-assistant-backups and rejects likely credentials in distributable files. It only allows main/_meta, assistant modules, safe default/sample config, API handlers, translations and documentation/license. It does not package development files, personal configuration.lua or native binaries. The optional hoedown library is absent; the built-in pure Lua Markdown parser is used.

Runtime resource paths are relative to assistant_paths.lua, not the writable profile. Metadata uses an explicit local path, avoiding require("_meta") collisions. Writable provider configuration is settings/assistant-configuration.lua under DataStorage; user UI choices remain settings/assistant.lua. To configure a real provider, privately copy/edit configuration.sample.lua at that profile path then restart. Do not place real credentials in the plugin source or APK. No production/shared profile config is imported automatically.

Default provider is explicitly offline/local UI only. It does not return simulated AI content and reports that no request was sent when asked to query. Opening the question/highlight editor no longer requires online status or triggers an update request. Real providers still require user configuration and an explicit query. This integration does not claim service/API compatibility or service authorization. Translation/auto-recap overrides remain opt-in.

The Makefile selects upstream calendar-version tags for runtime git-rev, since KOReader's Version/socketutil parser cannot parse the Alpha SemVer milestone. Historical Alpha APK119662 retains its original identity; this build fix is only in the post-Alpha branch.

Host integration tests use the current frontend/plugin and unchanged base native libraries at fa81dbb1 with isolated profile/PDF fixtures. Device tests are recorded separately in the run report; callback tests do not replace UI acceptance.
