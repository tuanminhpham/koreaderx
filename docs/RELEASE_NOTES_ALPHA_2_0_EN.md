# KOReaderX Test Alpha 2.0

This is the **Alpha 2.0 prerelease** of the isolated Android Test package, built from the latest AI Assistant integration. It keeps the Alpha 1.0 milestone and Git history intact.

- [English user guide](https://github.com/tuanminhpham/koreaderx/blob/v2.0.0-alpha.1/docs/ALPHA_2_0_USER_GUIDE_EN.md)
- [Prerelease and downloadable assets](https://github.com/tuanminhpham/koreaderx/releases/tag/v2.0.0-alpha.1)

## Changes since Alpha 1.0

- Bundles **AI Assistant**, its modules and required resources in a checked, vendored snapshot. A fresh clone can build from that snapshot without an undocumented external plugin folder; explicit synchronization remains available for plugin development.
- Adds the reader **Tools → AI Assistant** menu, private Test-profile configuration, selection translation through the compact toolbar's **AI** toggle, and dictionary popup integration.
- Preserves the compact right-hand **13-button toolbar**, highlight-page navigation, bookmarks, reader menu and persistent TOC panel. The toolbar remains above the actual visible KOReaderX footer, and the exposed page updates while TOC remains open.
- Preserves full-page PDF fitting, Page view and automatic footer/compact-toolbar defaults for a fresh profile/book without an overriding saved choice. Existing user choices remain respected.
- Retains the PDF annotation merge/ownership/transaction work already present in Alpha 1.0: all-page import, local metadata highlights/notes, tracked write-back and duplicate/conflict guards. These retained capabilities are documented more fully; they are not all new Alpha 2.0 changes.
- Fixes dictionary actions' compatibility with the integrated plugin and verifies HTTPS certificate chains **and hostnames** before sending provider credentials. HTTPS redirects are disabled for those requests.
- Adds a complete English user guide covering installation, display settings, every compact toolbar button, TOC, reimport, metadata/PDF write-back, Assistant and known limitations.

- Fixes bulk PDF command availability for note-only documents: **Write all highlights into PDF file** and **Delete all highlights from PDF file** count note-bearing highlights too and stay disabled when write-PDF is off or unset.
- Fixes ownership loss in a mixed imported/local **Write all highlights into PDF file** batch. Each item is reacquired after an imported transaction replaces metadata, so repeated write/close/reopen cycles replace the tracked ordinary annotation instead of creating another copy. Existing duplicate PDF annotations from older builds are not automatically repaired.

## Download and install

Download **`KOReaderX-Test-Alpha-2.0-arm64-v8a.apk`** for a 64-bit ARM Android device. ONYX TabXC is the target device used in the recorded testing. Validate it against **`SHA256SUMS.txt`** and inspect **`BUILD_INFO.json`** before installing.

| Identity | Value |
| --- | --- |
| Launcher name | KOReaderX Test |
| Package | `org.koreader.launcher.koreaderxtest` |
| versionName | `v2.0.0-alpha.1-KOReaderX-Test` |
| versionCode | `119742` |
| ABI | `arm64-v8a` |
| Build | `Arm64RocksDebug` — optimized native libraries, debuggable Android app |
| Tag | `v2.0.0-alpha.1` |

Before upgrading, back up **both the PDFs and the entire private Test profile**. This package keeps canonical highlights, notes, bookmarks and reading positions in the private profile’s `docsettings/` tree; **a Books-only backup is insufficient**. Include any book-adjacent sidecars that are present too. Install over the existing Test package with the matching signing certificate; do not uninstall or clear data. A successful installer result alone does not prove metadata preservation. For a new installation, allow the installer to install unknown apps if Android asks, then grant **KOReaderX Test** storage/all-files access when prompted. The Android permission screen wording varies by firmware.

This APK is restricted to books in:

```text
/storage/emulated/0/Books/test/KOReaderX_S10_ZWSqRJ0v
```

Its descendants are permitted; other folders are not. Place copies there and open them from the app's **File manager**. All-files permission does not lift the application path gate. This asset is not the separate unrestricted PDF-opening variant.

## AI Assistant setup

The shipped default is **offline** and contains no account credentials. Put your own trusted provider configuration in the private Test profile's `settings/assistant-configuration.lua`; see the guide's example and secure ADB copy instructions. Enable the plugin through **Tools → More tools → Plugin management**, then open **Tools → AI Assistant → AI Assistant Settings** inside a book.

To translate a passage, turn the toolbar's `ai` into **AI**, hold/drag to select several words and release. The toggle alone sends no request. Online use sends the selected passage and relevant prompt/book context to your chosen provider and may incur provider charges. Opening settings or cancelling the question editor does not send a query.

## Test results and evidence boundaries

The runtime baseline `e5ba9d225edc9ff2f28dfd25ab72e7fa13c69566` was verified on Test119722 before this release preparation. Final source/APK identity is in **`BUILD_INFO.json`**. The downloadable **`TEST_RESULTS.json`** records final-artifact checks, update preservation and the actual device smoke results after source freeze; use its named build and workflow scopes.

| Test | Status at source/documentation freeze | Scope |
| --- | --- | --- |
| Reader, overlays, footer, navigation, Assistant and PDF annotation host regressions | PASS_HOST | 143 inherited regression cases, 14 focused note-aware bulk-menu cases and one mixed-source bulk-write lifecycle regression in isolated profiles/fixtures (158 total). |
| Self-contained vendored-plugin build validation | PASS_HOST | 14 checks; excludes private/development files and rejects invalid snapshots. |
| HTTPS certificate/hostname checks | PASS_HOST | 23 local cases (10 actual LuaSec request cases plus 13 SAN/hostname cases), separate from provider generation. |
| Real toolbar-selected text → Gemini response | PASS_HISTORICAL_DEVICE | TabXC Test119722, nonstream `gemini-2.5-flash`, Vietnamese translation; provider/settings retained after restart. |
| Mistral response | NOT_QUALIFIED | Prior generation returned HTTP429; no answer. Testing stopped at the user's request. |
| Final Alpha 2.0 APK installation and UI flows | NOT_RUN_AT_SOURCE_FREEZE | Consult `TEST_RESULTS.json`; earlier APK evidence is not automatically a final-APK PASS. |
| Every streaming/provider combination, protected PDFs and all nested TOC hardware layouts | NOT_RUN | Not covered by the completed acceptance scope. |

No new paid AI request is part of this release publication. Host/API tests, Android input/UI observations, PDF-engine inspection and installer preservation are reported separately. A synthetic editor/engine check is not a claim that every external Android PDF editor has been qualified.

## Known issues and limitations

- **Isolated Test path:** only the exact Test tree above can contain books opened by this package. It has a separate private profile and is a debuggable evaluation build.
- **BOOX app freezing:** a frozen Test app on the tested firmware caused ADB `am start` to report **Error type 3** (enabled-state value `3`). Tapping its launcher icon unfroze and started it normally. This does not require uninstalling or clearing data.
- **Inherited File manager/background JNI crash:** the background book-information JNI/SIGABRT path remains unresolved. A passing reader or Assistant test does not demonstrate that it is fixed.
- **PDF selection geometry:** transient selection in Reflow, intrinsic PDF Rotate90 and some ordinary multi-page endpoint shrinking remain problematic. Device rotation is a different case. Use native PDF layout, inspect boundaries and keep backups before writing.
- **Import is a merge, not universal synchronization:** supported text markup is Highlight/Underline/Squiggly/StrikeOut with valid quad geometry. Unsupported annotation types are skipped; extracted text may be empty without a usable text layer. Changed/ambiguous sources and legacy ownership can require review. Externally deleted sources do not automatically delete metadata.
- **Opening prompt uses modification time:** Cancel acknowledges the current timestamp. Timestamp-preserving external edits may need manual import.
- **Write-all requires write-PDF on:** ordinary changes may remain staged until normal book close. Keep the option on through close, then verify the resulting PDF independently. Earlier items can succeed before a later item fails; write-all is not one document-wide atomic operation.
- **Recovery and deletion:** preserve PDF/sidecar/transaction backups on failure. Annotation deletion is not secure erasure and this is not a general bidirectional sync engine. This Test package’s canonical metadata is private; preserve its profile as well as the PDFs.
- **Protected/encrypted PDF qualification is incomplete.** Read-only paths, missing write permission, insufficient space or external edits can block publication.
- **Assistant:** your own service/account/model access is required. Gemini nonstream translation was demonstrated; streaming, every provider and optional summary/X-Ray/recap/notebook service outcomes are not all qualified. HTTP429 indicates provider limits, not a successful answer.
- **TOC coverage:** ordinary flat-TOC selection/persistence and host branch cases have coverage; not every nested hardware layout was exercised. Modal menus other than reader TOC keep their own display and dismissal behavior.

## Assets and reproducibility

The release contains the APK, **`SHA256SUMS.txt`**, **`BUILD_INFO.json`**, the English guide and verification results. Exact source/dependency revisions, package/version/build type, APK SHA-256 and public certificate fingerprint are recorded in `BUILD_INFO.json`. The tagged repository includes the Assistant snapshot, synchronization/validation tools and build instructions. Signing keys, API credentials, device profiles and personal books are excluded.

Keep the existing Alpha 1.0 release/tag unchanged. This prerelease is published from its dedicated Alpha 2.0 branch/tag without merging into the upstream main branch.
