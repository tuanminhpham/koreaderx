# KOReaderX Test Alpha 2.0 — User Guide

This English guide describes the isolated Android **KOReaderX Test Alpha 2.0** prerelease and its actual menu labels. Screens and system-permission wording can vary with Android firmware. The guide is self-contained and does not depend on screenshots.

| Item | Value |
| --- | --- |
| Android launcher name | KOReaderX Test |
| Package | `org.koreader.launcher.koreaderxtest` |
| APK | `KOReaderX-Test-Alpha-2.0-arm64-v8a.apk` |
| ABI | `arm64-v8a` (64-bit ARM) |
| versionName | `v2.0.0-alpha.1-KOReaderX-Test` |
| versionCode | `119742` |
| Build variant | `Arm64RocksDebug`: optimized native libraries with a debuggable Android application |
| Release tag | `v2.0.0-alpha.1` |

Get the APK, checksums, build identity and verification record from the [Alpha 2.0 prerelease](https://github.com/tuanminhpham/koreaderx/releases/tag/v2.0.0-alpha.1). `BUILD_INFO.json` identifies the exact source commit, dependencies and public signing certificate. `TEST_RESULTS.json` distinguishes final-artifact/device checks from earlier runtime tests. Read [the release notes](RELEASE_NOTES_ALPHA_2_0_EN.md) before updating.

## Contents

- [Installation and upgrade](#installation-and-upgrade)
- [Display configuration](#display-configuration)
- [Compact toolbar reference](#compact-toolbar-reference)
- [Reimport after another application changes the PDF](#reimport-annotations-after-another-application-changes-a-pdf)
- [Import all embedded highlights into metadata](#import-all-embedded-pdf-highlights-into-metadata)
- [Write all metadata highlights into the PDF](#write-all-metadata-highlights-into-the-pdf)
- [AI Assistant](#ai-assistant)
- [Troubleshooting and known limitations](#troubleshooting-and-known-limitations)
- [Verification scope and short manual checks](#verification-scope-and-short-manual-checks)

## Installation and upgrade

Download `KOReaderX-Test-Alpha-2.0-arm64-v8a.apk` and `SHA256SUMS.txt` from the **KOReaderX Test Alpha 2.0** prerelease. This APK targets 64-bit ARM Android devices, including the ONYX TabXC. Compare the APK's SHA-256 with `SHA256SUMS.txt`; see `BUILD_INFO.json` for version, build type and public signing-certificate fingerprint.

The Android launcher name is **KOReaderX Test**, package `org.koreader.launcher.koreaderxtest`. It has a separate profile and can coexist with a differently packaged reader. This prerelease is the isolated Test build.

### Back up before an update

1. Close the book using the top menu's **File manager** folder icon, then exit normally to flush settings.
2. Copy the entire Test books directory, including any hidden files and `.sdr` directories that are present. This preserves the PDFs and book-adjacent files, but does not include this Test package’s canonical book metadata.
3. **Back up the private Test profile as well. This is required to preserve highlights, notes, bookmarks and reading positions.** Its directory is `/data/user/0/org.koreader.launcher.koreaderxtest/app_koreaderx-test`; canonical book metadata is in its `docsettings/` tree. **A Books-only backup is insufficient.** Android file managers cannot normally access the private profile, and Android automatic application backup is disabled for this APK. The profile also contains preferences and may contain AI credentials; keep its backup private.

Advanced backup from an authorized ADB host, with the app exited and `SERIAL` replaced by the device serial:

```sh
adb -s SERIAL exec-out run-as org.koreader.launcher.koreaderxtest \
  tar -cf - app_koreaderx-test > koreaderx-test-profile.tar
adb -s SERIAL exec-out tar -cf - \
  /storage/emulated/0/Books/test/KOReaderX_S10_ZWSqRJ0v \
  > koreaderx-test-books.tar
```

Check both exit statuses and inspect both archives before relying on them: redirection can leave a partial archive if a command fails. `run-as` works for this debuggable Test APK, not arbitrary packages.

### Install or update

1. Open the downloaded APK in Android's file manager. If Android blocks installation, allow that file manager/browser to **install unknown apps** in Android Settings, then reopen the APK. System wording varies by firmware.
2. For an update, confirm Android offers to update **KOReaderX Test**. The package and signing certificate must match the installed Test app. Do not uninstall to work around a signature error; uninstalling deletes private data.
3. Open **KOReaderX Test** and grant storage access. On Android 11+, the app says **“Please allow the app to manage all files.”** and opens its Android all-files-access settings. Enable access for **KOReaderX Test**, then return. Older Android versions request storage permission instead. Assistant network access has no separate runtime permission dialog.
4. Reopen a backed-up Test PDF and check reading position, highlights, notes, bookmarks and display settings. Android reporting installation success alone does not prove preservation.

For ADB updates, verify the device, package, certificate and backup first, then run `adb -s SERIAL install -r VERIFIED.apk`. Do not uninstall or clear data.

### Where to put PDFs

The Test File manager is locked to this exact directory and its descendants:

```text
/storage/emulated/0/Books/test/KOReaderX_S10_ZWSqRJ0v
```

On TabXC this is internal storage `Books/test/KOReaderX_S10_ZWSqRJ0v`; `/sdcard/Books/test/KOReaderX_S10_ZWSqRJ0v` is its alias. Create it with an Android file manager if needed and put **copies** of books there. Other folders under `Books/test` are outside the gate. Android all-files permission does not remove this application restriction. Symlinks to books outside the tree do not bypass it.

Open **KOReaderX Test**, navigate its File manager within this folder and tap the PDF. From the reader, the top menu's folder icon closes the book and returns to File manager. Android **Open with** does not allow Test to read arbitrary paths: copy a PDF into the permitted folder and open it from the app.

Do not copy a whole production profile into Test: its settings audit rejects stale absolute paths outside the Test profile/books tree.

## Display configuration

### Footer and compact toolbar

The **KOReaderX status bar** is the reading footer at the bottom of the page. It is separate from Android's clock/notification bar and Android navigation buttons.

For a fresh profile and a PDF without saved display choices, the release shows the footer and a vertical compact **13-button** toolbar at the right, uses full-page fitting and single-page view. Existing saved profile defaults or per-book choices take precedence.

1. Open a PDF; the toolbar appears automatically after reader/footer layout is ready.
2. Tap **⋮** at the toolbar bottom, or the top-center menu area, to open the top menu.
3. In the **Settings** gear tab open **Status bar**. Under **Progress bar**, **Show progress bar** enables progress display. If you hid the footer by tapping it, tap its bottom touch area until it is visible again. With **Lock status bar** checked, taps do not change its mode; clear that option first. Turning **Show progress bar** off then on also restores a visible footer, but changes that preference.
4. Keep existing footer items/order/font/height unless you want to change them. **Status bar items**, **Arrange items in status bar**, item-font controls and **Height** customize the KOReaderX footer.
5. Under **Settings → Navigation → Skim dialog position: bottom**, choose **Bottom** for compact mode. The retained **Top** choice also selects the same right-hand compact layout in this fork. **Center** selects the full skim dialog. These labels do not imply a draggable compact toolbar.

The compact toolbar cannot be dragged. Its frame and touch targets end at the actual top of the visible footer; with the footer hidden they end at the bottom of available reader space. Rotation, UI scaling and footer-height changes relayout the same toolbar. Other modal menus/dialogs can temporarily cover reader controls.

### Reopen a hidden toolbar

Open the top menu's **Navigation** tab and tap **Skim document**. This also enables automatic toolbar opening for that book on future opens. Android Back can hide the compact toolbar and saves that choice for the current book.

The optional **Settings → Status bar → Long-press on status bar to skim** shortcut opens it when you hold the visible footer. This shortcut alone does not reset a saved per-book auto-show-off choice; use **Skim document** to restore automatic opening too. A fresh profile does not require long-press-to-skim and that shortcut is initially off.

### Verify Fit full and Page

1. Dismiss covering dialogs/TOC, then tap the bottom configuration area or swipe upward from it to open the bottom configuration menu.
2. Select its page-fit icon panel. Set **Zoom to** to the **page** icon/choice and **Fit** to **full**. This combination fits the full page; **content** and **width** are different choices.
3. Select the page-view icon panel. Under **View Mode**, choose **page**, rather than **continuous**.
4. Close the menu/book normally and reopen to check persistence.

Tapping a value changes the current book. Holding a supported value opens **“Set default … to …?”**; **Set as default** saves a shared default for books without their own choice. It does not erase saved choices in other books. A hold is not required merely to save the current book.

Display choices saved for the current book take priority over shared defaults and built-in defaults. A later user choice, such as Fit width, persists and is not forced back after a page turn or restart. Footer presentation and the AI toggle are shared Test-profile settings; toolbar auto-show can be stored per book.

## Compact toolbar reference

The following table lists all 13 compact buttons **from top to bottom** in the normal layout. The full centered skim dialog has a different layout; its ±10 controls/page-number control are not extra compact buttons.

| No. | Identification | Tap | Hold | Conditions and limits |
| --- | --- | --- | --- | --- |
| 1 | **▷** | Next PDF page. | No assigned action. | Remains at final page when already there. |
| 2 | **◁** | Previous PDF page. | No assigned action. | Remains at page 1 when already there. |
| 3 | **⏩** | Next **page with a highlight**. | Last bookmark/annotation entry. | Tap skips page-only bookmarks and highlights on the current page. Hold is not restricted to highlights. |
| 4 | **⏪** | Previous **page with a highlight**. | First bookmark/annotation entry. | Same highlight-only tap scope; skips current page. Hold is not restricted to highlights. |
| 5 | **➡** | Next bookmarked/annotated page. | Last bookmark/annotation entry. | Includes highlights/notes and page bookmarks; skips current displayed page. |
| 6 | **⬅** | Previous bookmarked/annotated page. | First bookmark/annotation entry. | Same mixed annotation-list scope as **➡**. |
| 7 | **⏭** | Next chapter start from TOC ticks. | Last page. | No later chapter means no tap destination. Chapter-navigation TOC-level filtering can affect starts. |
| 8 | **⏮** | Previous chapter start. | Page 1. | No earlier chapter means no tap destination. |
| 9 | **Bookmark outline / filled bookmark** | Toggle the current page bookmark; icon reflects its state. | Open **Bookmarks** and close the toolbar overlay. | A highlight alone is not a page bookmark. **Skim document** reopens the toolbar. |
| 10 | **ai / AI** | Toggle automatic AI translation of subsequent text selections: lowercase off, uppercase on. | No assigned action. | Requires loaded/configured Assistant and connectivity for online providers. A tap alone sends no text. Enabling sets default selection action **AI Translate**; disabling sets ordinary **Highlight**. |
| 11 | **↺** | Return to the origin saved when toolbar navigation first moved away from its opening location. | No assigned action. | Does nothing before toolbar navigation saves an origin. A return consumes that origin; it is not a general undo. |
| 12 | **☰** | Open **Table of contents**. | No assigned action. | Repeated taps keep one existing panel. A document with no TOC has no chapter targets. |
| 13 | **⋮** | Open the reader top menu. | No assigned action. | Access Navigation, Settings, Tools and File manager tabs. |

Controls are not dynamically greyed out when no destination exists: unavailable navigation simply does not move to a new page. In mirrored layouts directional symbols can be mirrored/inverted.

Selection gestures outside the toolbar reach the reader once, including a hold/drag crossing the toolbar before release. Turn **AI** off or explicitly select the ordinary highlight action when you want saved highlights rather than automatic translation.

### Persistent Table of contents panel

1. Tap **☰**. **Table of contents** appears on the left, leaving part of the book visible to the right. It leaves the compact toolbar/footer clear.
2. Tap a title. The reader moves to it and immediately redraws the exposed book page; the same TOC stays open for successive selections.
3. Use TOC pagination/scroll controls. On nested TOCs, tap the expand/collapse region at the left of a row to toggle branches and tap the title to navigate. Page updates retain menu position/expanded nodes and update the current-entry mark.
4. Tap the **exposed book page outside the panel** to close TOC. That tap is consumed and does not also turn the page, select text or open a dictionary. The page, toolbar and footer remain.

Toolbar taps and footer gestures still reach their respective controls; those are not outside-book dismissal taps. Tapping **☰** again does not duplicate the panel. Rotation relayouts both overlays. Normal Back/close gestures are intentionally consumed by this reader TOC; dismiss with the exposed-page tap. Closing the book/app cleans it up. Other menus keep their own dismissal behavior.

The TOC search/filter command can rebuild the menu for results. Ordinary selections/list movement/branch expansion do not close/recreate it. Hierarchical branches have host coverage; device acceptance used a flat PDF TOC, not every nested layout.

## Reimport annotations after another application changes a PDF

KOReaderX keeps two different forms of annotation data: annotations embedded in the PDF, and its own highlights, notes and source mappings in the book's metadata (the sidecar). Importing reads the first into the second; it does not modify the PDF.

1. Back up the PDF and its KOReaderX metadata. Close the book normally in KOReaderX Test before editing it elsewhere. Do not let two applications write the PDF at the same time.
2. In the other application, add or edit a supported text annotation and save **the same file at the same path**.
3. Reopen that file in KOReaderX Test with **Reflow** off. The opening prompt is: **“The PDF is new or has changed. Import its embedded annotations without removing existing highlights?”** Its buttons are **Cancel** and **OK**.
4. Choose **OK** to scan the whole PDF and merge supported annotations into metadata. Existing KOReaderX highlights and page bookmarks are retained, and the embedded originals remain in the PDF. Read the completion report; a conflict count is a request for review, not confirmation that external edits replaced local data.
5. Choose **Cancel**, press Back, or tap outside the prompt to skip import. Existing metadata and PDF annotations remain. This records the file's current modification time as seen, so the same timestamp will not trigger the prompt again. You can import later using **Typeset → Highlights → Import embedded PDF annotations**.

The opening check compares the file's filesystem modification time with the time recorded for this book. It also appears for a newly opened PDF that has not yet been acknowledged. It is not a continuous file watcher or a content-hash change detector; a change that preserves the timestamp may not produce a prompt. If the PDF changes while it is open, annotation operations can refuse to proceed with **“PDF changed outside KOReader. Close and reopen the document before importing or editing annotations.”** Close and reopen before retrying.

Reimport merges new sources and skips unchanged sources already known to metadata. It preserves local notes and overrides when an existing source has changed externally and reports a conflict rather than silently overwriting them. It does not automatically remove metadata items just because another application deleted their PDF originals. A rewritten PDF with new object numbers can be recognized when a complete original annotation snapshot has exactly one match; ambiguous cases are reported for review. Two independent annotations on the same words are not assumed to be duplicates.

A PDF saved under a different filename or path is a separate book for normal metadata lookup. Do not expect its prior reading position, local highlights or deleted-source list to follow automatically. A new file may contain the same embedded annotations, which it can import into its own metadata. This isolated Test package keeps canonical sidecars in its private profile’s `docsettings/` tree. Back up that private profile alongside the original PDFs; do not rely on finding a sidecar next to each PDF.

### Locally deleted items and deliberate replacement

Deleting an imported highlight while **Write highlights into PDF: off** removes it from KOReaderX metadata and remembers its source in a local deleted-source list. The original annotation remains embedded in the PDF and can still be visible there. Ordinary import skips that unchanged source instead of bringing the item back. To restore such sources deliberately, open **Typeset → Highlights → Reimport locally deleted PDF annotations…**, review **Reimport deleted PDF annotations: preview**, then choose **Reimport listed annotations**. **Cancel** leaves the state unchanged. This resets the deleted-source list and imports sources still present in the PDF; it cannot restore a PDF annotation that was physically deleted.

Use **Replace KOReader highlights from PDF…** only when you intend to rebuild highlights and notes from the current PDF. Its **Replace KOReader highlights from PDF: preview** lists the metadata items to be removed, including local/legacy items that may exist only in KOReaderX. Page bookmarks and the PDF are retained and a complete sidecar backup is kept. Choose **Replace…** and confirm **“Replace all N listed highlights and reset the deleted-source list?”** to perform the replacement. This discards local-only highlight/note information and resets the deleted-source list; ordinary import is the safer merging action. Replacement does not provide an automatic conflict resolver for every rewritten or edited PDF.

## Import all embedded PDF highlights into metadata

1. Open a backed-up test copy of the PDF and turn **Reflow** off. Open the reader menu, select the **Typeset** tab, then **Highlights → Import embedded PDF annotations**. The command is unavailable in Reflow mode.
2. Confirm **“Import embedded PDF annotations? Existing KOReader highlights and the PDF originals will be kept.”** with **OK**. Choose **Cancel** to make no changes.
3. Read the result: **“Imported: N. Already imported or deleted locally: N. Invalid: N. Conflicts requiring review: N.”** Import scans every page, rather than just the visible page or selected text.
4. Review the imported items through the navigation menu's **Bookmarks** list, or tap a visible imported highlight. Close and reopen the book, then verify that the notes and highlights are still available.

Supported embedded types are text **Highlight**, **Underline**, **Squiggly** and **StrikeOut** annotations with valid text-markup quad geometry. Squiggly annotations use the underline style in KOReaderX metadata. Standalone sticky notes, ink/freehand strokes, shapes, links and other PDF annotation types are not imported by this command.

The highlighted text is extracted from the PDF text layer underneath the markup geometry. It can be empty on a scanned page without usable text. PDF annotation **Contents** becomes the KOReaderX note; the author is retained. A display color is mapped to the nearest KOReaderX highlight color. The source mapping separately retains the original raw color and other supported source properties, so a palette approximation in metadata does not itself recolor the PDF. Import leaves embedded originals and PDF bytes unchanged.

Running import again on unchanged sources should report zero new imports; source identities and complete raw snapshots provide duplicate detection. Geometry alone does not establish ownership. Existing independent annotations that cover the same text may both be valid. Unchanged locally deleted sources remain skipped. Changed sources, ambiguous object renumbering and legacy highlights without trusted provenance can increase the conflict count rather than being imported twice or overwritten. Review nonzero **Invalid** and **Conflicts requiring review** counts before continuing; the command does not promise an exact merge of every third-party annotation format.

## Write all metadata highlights into the PDF

Saving a highlight in metadata and embedding it in the PDF are separate operations. Metadata is needed for KOReaderX-specific state even after a PDF has been written. Back up both before writing.

1. Use a writable PDF copy in the Test book directory. Close other editors. If the file requires a password, unlock it first. The file and its containing directory need enough permission and free space for the staged PDF, sidecar and backup files.
2. Open **Typeset → Highlights → Write highlights into PDF: off → On**. The entry then shows **Write highlights into PDF: on**. Tapping **On** changes the current book; holding it changes the general default. The current book's saved choice takes priority over that general default. A read-only file cannot enable this mode; KOReaderX explains that highlights can still be saved in settings but cannot be written to that location.
3. In the same submenu, choose **Write all highlights into PDF file**. It is enabled only while write-PDF is on and the book has at least one metadata highlight or highlight note. Confirm **“Are you sure you want to write all KOReader highlights into PDF file?”** with **OK**.
4. Read **“N highlights written into PDF file”** and any error messages. The command processes all metadata highlights/notes with highlight geometry throughout the document; page bookmarks are not written as PDF markup.
5. Keep write-PDF on and close the book normally before copying or opening the result elsewhere. For ordinary KOReaderX-created highlights, native changes are staged and published when the document closes. A notification alone is not proof that every pending change has reached the file. Turning write-PDF off before closing can discard pending ordinary PDF changes while retaining metadata.
6. Reopen in KOReaderX Test and review the items. Then open a copy of the resulting PDF in an independent PDF reader and check the affected pages, colors, note text and annotation count. Keep the metadata backup until this comparison is complete.

The command writes the metadata geometry, color, supported style and note into the PDF. Text-markup content is represented by quads over the PDF text; the note is stored as annotation **Contents**. Supported native styles are highlight, underline and strikeout. Some display styles have no equivalent PDF markup; their appearance cannot be promised to match another reader exactly. On imported items, unchanged source properties are retained; local color/style/boundary overrides are applied by the write-all action, and note contents are updated. A multi-page highlight can require one PDF annotation per page.

For an imported annotation, KOReaderX uses its source identity and saved raw snapshot to update that source, including adding/removing page fragments after a boundary change. For a newly created KOReaderX highlight, tracked owned PDF parts are replaced rather than adding another copy each time. It does not delete an unrelated annotation just because it overlaps the same words. Repeating write-all/import on unchanged, trusted sources is covered by host regression tests, including three write/close/reopen cycles with a mixed imported/local batch. This prevents the ownership-loss duplicate found during release testing; it does not automatically remove duplicate PDF copies already produced by an older build. Keep a pre-write backup and still compare counts when a third-party editor has rewritten the file. Missing/stale ownership, externally changed sources and ambiguous legacy data can block a write instead of guessing which PDF object belongs to the highlight. Preserve the file, sidecar and transaction backups and reconcile before retrying.

Write-all is a sequence of item operations, not a single all-document transaction: an error can stop the loop after earlier items have succeeded. The count reports items processed, not a guarantee that every source was writable. Imported-item changes use paired PDF/metadata transactions with retained backups; ordinary items retain staged write-on-close behavior. Insufficient storage, read-only paths, password/candidate-open failures or concurrent external edits can prevent completion. Protected/encrypted PDF compatibility has not been fully qualified, and this release does not promise to bypass document protection.

### Deletion and synchronization policy

- **Write highlights into PDF: off** keeps normal edits local. A local deletion remembers known PDF source parts so ordinary import does not immediately re-add them; it does not delete their embedded originals.
- With write-PDF **on**, deleting a tracked imported or owned item can remove its tracked native parts as well. Other annotations are retained. This is not a complete bidirectional synchronizer for arbitrary external edits.
- **Delete all highlights from PDF file** is a separate, confirmed command in the write-PDF submenu. It removes tracked PDF parts while keeping metadata highlights. It is not the same as deleting the metadata, and a later write-all can embed those remaining highlights again. Untracked foreign annotations are not selected for deletion merely by matching geometry.
- Deleting an annotation is not secure erasure. Incremental PDF history and retained transaction/sidecar backups may still contain earlier data. Keep backups for recovery and manage their storage deliberately.
- This isolated Test profile enforces directory-based metadata in its private `docsettings/` tree. General KOReader code warns about hash-based storage when PDF bytes change, but this Test build does not use that layout. Retain both the private-profile backup and the PDFs.

### Annotation limitations and validation scope

Source review and isolated host tests verify merging, idempotent reimport, note/color retention, tracked ownership, duplicate prevention and transaction guards. Those tests do not establish a new TabXC UI PASS for every import/write dialog. The release test record must identify which UI flows were actually exercised on the final APK and leave the others **NOT_RUN** or **BLOCKED**.

Known inherited geometry limitations include transient selection in Reflow, selection on pages with intrinsic PDF Rotate90, and shrinking an ordinary multi-page highlight across its last endpoint page. These are distinct from viewing a saved highlight after rotating the device. Use native PDF layout for annotation editing, inspect boundaries before writing, and keep the backup when a saved result is suspect.

## AI Assistant

Open a book before using the assistant. The reader menu is **Tools → AI Assistant**. This plugin is reader-only; its menu is not available in File manager. If it is disabled, open **Tools → More tools → Plugin management**, enable **AI Assistant**, and restart KOReaderX when prompted.

The packaged default is **offline**. You can open the question editor and settings locally, but the app does not supply an AI account, key or simulated answer. A query without a configured service reports that no request was sent.

### Configure your own provider

Provider credentials and endpoints are configured in a Lua file, not in the provider radio buttons. Start with the packaged `plugins/assistant.koplugin/configuration.sample.lua`; keep only the providers you intend to use and replace the placeholders in your private copy. For example, the following is a minimal Gemini configuration using the model exercised on the verified Test119722 build:

```lua
return {
    provider = "gemini",
    provider_settings = {
        gemini = {
            model = "gemini-2.5-flash",
            base_url = "https://generativelanguage.googleapis.com/v1beta/models/",
            api_key = "your-gemini-api-key", -- replace only in your private copy
            additional_parameters = {
                thinking_budget = 0,
            },
        },
    },
    features = {},
}
```

The top-level `provider` selects an entry in `provider_settings`. Standard entries use `model`, `base_url`, `api_key` and optional `additional_parameters`; provider-specific fields are documented in the sample. Only use endpoints and models available to your account. HTTPS requests validate the server's certificate chain and hostname against the bundled CA file. Do not disable verification to work around a certificate error.

Save the private copy as `settings/assistant-configuration.lua` inside the active KOReader profile. For **org.koreader.launcher.koreaderxtest**, the Android path is:

```text
/data/user/0/org.koreader.launcher.koreaderxtest/app_koreaderx-test/settings/assistant-configuration.lua
```

This is app-private storage, not a file in the Books folder. On this debuggable Test package, an authorized ADB session can copy a trusted private file without printing its contents. Exit the app normally and back up the Test profile first, then use the selected device serial:

```sh
adb -s SERIAL shell "run-as org.koreader.launcher.koreaderxtest sh -c 'umask 077; cat > app_koreaderx-test/settings/assistant-configuration.lua'" \
  < /private/path/assistant-configuration.lua
```

Open the app again after replacing the file: configuration is loaded when the plugin starts. This file is executable Lua, so use a trusted local copy. Keep real credentials out of the repository, APK, screenshots and shared logs. The packaged default/sample files remain unchanged.

In **Tools → AI Assistant → AI Assistant Settings**, select a configured **AI Model provider**. This immediately switches the handler and saves the choice. The app remembers your UI selection across restarts. Changing the top-level `provider` in the private configuration intentionally resets that selection once; an unchanged configuration does not reset it on every launch.

For the behavior demonstrated on TabXC, turn **Enable stream response** off. Set **AI Language** to your desired response language. The acceptance run used the literal stored value `vietnam`, and Gemini returned Vietnamese. Streaming exists in the plugin, but live-provider streaming was not part of that acceptance run. Fresh profiles initially have the streaming checkbox enabled, so explicitly turn it off for this workflow.

### Translate selected text with the compact toolbar

1. Open a book and tap the compact toolbar's `ai` button so it reads **AI**. This enables automatic AI translation for a subsequent selection; tapping the button alone does not send text.
2. Press and hold at the beginning of a short passage, drag across the words you want, then release. A multiword selection is the clearest way to use this action. A single word normally opens the dictionary, and a prolonged final hold can open the highlight menu instead.
3. The loading popup shows the provider/model. When the response arrives, **Assistant: Translate** shows the selected passage and answer.
4. Tap **Close** to return to the same book page. The compact toolbar and status bar remain available. Tap **AI** again to turn automatic translation off; `ai` indicates it is off and ordinary highlighting becomes the default selection action.

The toolbar toggle is separate from **Use AI Assistant for 'Translate'** in assistant settings. That checkbox controls the ordinary Translate action's override; it is not required for the compact toolbar's AI selection flow.

Selecting text for this translation does not itself save a new annotation. **Add Note** and **Save** are separate, intentional actions in the result viewer. Selected text and relevant prompt/book context are sent to the provider when a query runs; choose a passage you are comfortable sending.

### Ask a question and use dictionary actions

Choose **Tools → AI Assistant → Ask the AI a question**, type your question and tap **Ask**. Opening the editor does not call a service. **Cancel** or the title-bar close button closes it without sending. Even without a selection, this is a book-context question flow, not a context-free chat launched from File manager.

A dictionary popup can include **Dictionary (AI)** and **Wikipedia (AI)** actions. Their visibility is controlled by **Show Dictionary(AI) in Dictionary Popup** and **Show Wikipedia(AI) in Dictionary Popup** in assistant settings. Changes apply to the next dictionary popup. Those actions send a request when activated with a real provider.

Other reader menu actions include **Book Summary & Recs**, **AI X-Ray**, **AI Recaps**, and **NoteBook (Saved AI Conversations)**. Their service outcomes were not covered by the demonstrated translation test. Leave **Enable Auto Recap** off unless you want the book-opening recap prompt. **Copy entered question to the clipboard** is on by default and can be disabled in settings. **Auto-save conversations to NoteBook** is off by default; with it off, use **Save** explicitly to store a conversation. **Copy** places the displayed result on the clipboard, and **Add Note** invokes the reader's annotation workflow.

### Cancel a request or handle an error

During a nonstream request, dismissing the loading popup cancels the local request task. During streaming, use **⏹ Stop** or the close icon. Cancellation can stop waiting locally; it cannot retract content already sent to the service. A cancelled request may show **Request cancelled by user.**

An API error dialog offers **Close** and **Settings**. Check your private provider entry, account access, endpoint/model and connectivity before deliberately trying again. For HTTP429 / **Rate limit exceeded**, stop retries and check the provider's limits or select another configured provider. An HTTP200 model-list response only proves authentication/model listing; it does not prove that generation is available.

On the verified Test119722 run, Gemini `gemini-2.5-flash` produced a Vietnamese translation through the actual toolbar/selection UI in nonstream mode. Mistral generation returned HTTP429 twice; no Mistral answer was obtained, and testing was stopped. Gemini selection and settings survived a cold restart; no additional generation request was sent after that restart.

### Saved state

UI choices are stored in the Test profile's `settings/assistant.lua`; private endpoint/key configuration stays in `settings/assistant-configuration.lua`. The compact toolbar stores `ai_translate` and `default_highlight_action` in `settings.reader.lua`. Closing the reader/app normally flushes settings. Keep backups before replacing configuration or updating an APK; update the existing Test package with the matching signer rather than uninstalling or clearing data.

## Troubleshooting and known limitations


- **Install succeeds but data seems missing:** check the Test package and exact book path. A moved/renamed PDF may use a different sidecar/history. Keep the backup and inspect PDF plus `.sdr` before recovery; do not clear data.
- **Update signature mismatch:** compare package/certificate with the installed Test. Keep the old app; a new signing key cannot update it.
- **PDF outside permitted folder:** copy it into `Books/test/KOReaderX_S10_ZWSqRJ0v`. All-files permission does not disable the gate.
- **Footer hidden:** check its bottom touch area, **Lock status bar** and **Progress bar → Show progress bar** without resetting item order/font.
- **Toolbar missing for one book:** **Navigation → Skim document** restores saved auto-show. **Skim dialog position: center** is the full dialog.
- **TOC ignores Back:** tap the exposed book area; toolbar/footer taps go to those controls.
- **Highlight arrows do not move within the current page:** they navigate between highlighted pages and intentionally skip that page.
- **A modal menu covers controls:** close it. The footer-clearance guarantee applies to compact toolbar/reader TOC, not every dialog.
- **Known platform issue:** the pre-existing File manager/background book-information JNI/SIGABRT path remains unresolved; a successful reader test does not prove it fixed. Preserve logs/backups if it recurs.

- **Import command unavailable:** open a PDF with Reflow off. Only supported text-markup annotations with valid quad geometry can be imported. Scanned pages without a text layer can have empty extracted highlight text.
- **Changed PDF did not prompt:** close/reopen and use **Typeset → Highlights → Import embedded PDF annotations**. The opening prompt uses modification time; Cancel acknowledges that timestamp. A timestamp-preserving external edit may not trigger a prompt.
- **Import reports conflicts or seems to skip items:** unchanged known or locally deleted sources are intentionally skipped. Changed/ambiguous sources and untrusted legacy ownership require review. Do not repeatedly replace metadata without backing it up.
- **Write-all is disabled:** enable **Write highlights into PDF: on** and ensure metadata contains at least one highlight or highlight note. Check filesystem write access and available storage.
- **Another reader cannot see a new highlight:** metadata-only saving does not embed it. Use write-all, keep write-PDF on, close normally, then inspect the actual resulting file. Do not mistake a KOReaderX overlay for proof that the PDF was written.
- **A write or recovery error appears:** preserve the PDF, sidecar and `.koreaderx-*` transaction/backup files; close the book before further editing. Do not delete recovery evidence or clear application data to retry.
- **Selection extends beyond the intended text:** native selection in Reflow, intrinsic Rotate90 pages and some ordinary multi-page endpoint shrinking remain known limitations. Review boundaries in native layout before embedding and retain the backup.
- **Protected PDF fails to write:** ensure it can be unlocked and the path is writable. Protected/encrypted PDF behavior is not fully qualified.
- **BOOX has frozen the app:** on the tested firmware, ADB showed an application enabled-state value of `3` and `am start` reported **Error type 3**. Tapping **KOReaderX Test** in the BOOX launcher unfroze it and started it normally. Check the firmware's app-freezing controls before retrying; do not uninstall to work around this state.
- **Assistant is missing:** open a book and check **Tools → More tools → Plugin management → AI Assistant**. Restart after enabling it.
- **Assistant is offline or returns an error:** supply your own trusted private provider configuration, select a configured provider, check connectivity/account/model access and inspect the error. For HTTP429, stop retries and check provider limits. Turning streaming off matches the exercised Gemini workflow. Online streaming, provider/model combinations and optional Assistant features are not all qualified.

The Test path restriction, debug Android variant, incomplete third-party annotation reconciliation and the inherited geometry/JNI issues make this an evaluation prerelease. It is not a substitute for preserving the original PDF and metadata.

## Verification scope and short manual checks

The runtime baseline was commit `e5ba9d225edc9ff2f28dfd25ab72e7fa13c69566`, verified as Test versionCode `119722`. Alpha 2.0 adds release documentation, a self-contained build-validation path and a focused reader-menu fix: bulk PDF commands include highlights with notes and remain disabled when write-PDF is off or unset; mixed imported/local bulk writes retain ordinary annotation ownership across transaction table replacement. The Assistant runtime remains the verified vendored integration. The final build's source commit and hashes are in `BUILD_INFO.json`. Evidence available when this guide was frozen is separated below; the release's `TEST_RESULTS.json` records final-APK installation, artifact checks and any subsequent device smoke tests.

| Check | Recorded status | Scope |
| --- | --- | --- |
| Focused reader/annotation/Assistant host regression | PASS_HOST | 158 tests: 143 inherited reader/annotation/Assistant regression cases, 14 focused bulk-menu cases for the note-count fix, and one mixed-source bulk-write lifecycle regression, using isolated profiles/fixtures. |
| Vendored-plugin build-input validation | PASS_HOST | 14 checks, including independent use of the vendored snapshot, excluded private configuration, hash validation and invalid-input rejection. |
| Assistant HTTPS transport | PASS_HOST | 23 cases: 10 actual local LuaSec request cases and 13 hostname/SAN cases; no paid provider calls. |
| Fresh defaults | PASS_HOST | Isolated profile/fixture tests; this is not a first-install TabXC test. |
| Toolbar/selection → Gemini translation | PASS_HISTORICAL_DEVICE | Test119722, real TabXC UI, nonstream `gemini-2.5-flash`, Vietnamese answer; settings persisted after restart. No new generation call is implied for Alpha 2.0. |
| Mistral generation | NOT_QUALIFIED | Earlier requests received HTTP429; no successful answer. Testing was stopped at the user's request. |
| Final Alpha 2.0 APK update/preservation and reader/Assistant smoke | NOT_RUN_AT_SOURCE_FREEZE | See `TEST_RESULTS.json` for actual later results; earlier APK results are not final-APK acceptance. |
| Reimport/import-all/write-all through final APK UI; independent viewer | NOT_RUN_AT_SOURCE_FREEZE | Host logic passed. Any later synthetic-PDF TabXC checks are separately identified in `TEST_RESULTS.json`. |
| Streaming, every provider, nested TOCs on hardware and protected PDFs | NOT_RUN | Outside the completed acceptance scope. |

For any unverified device workflow, use only expendable PDF copies in the permitted Test directory and back up their metadata first:

1. **Fresh installation/defaults:** on a separate authorized Android profile/device, install the APK, grant permission and open a new PDF copy. Check visible footer/right compact toolbar, full-page fit and Page mode. Do not reset the existing Test profile to perform this check.
2. **Update preservation:** back up, install with matching package/signer, then compare the same PDF's reading position, highlights, notes, bookmarks and settings before/after reopening.
3. **External reimport:** close the test PDF, add a supported embedded highlight with another editor, save the same path and reopen. Verify the exact prompt; try Cancel, then manual import, then import again. Check counts, notes and PDF bytes where appropriate.
4. **Write-all and independent verification:** create a local metadata highlight/note with write-PDF off, enable on, use write-all, leave on and close normally. Open the output in another PDF reader and check count/page/text/color/note; reopen KOReaderX and verify metadata remains.
5. **Reader overlays:** use toolbar navigation, select several TOC titles successively, tap the exposed page to dismiss and rotate while TOC is open. Check there is one panel, the page updates and footer/toolbar remain accessible.
6. **Assistant local smoke:** open settings/question editor and Cancel. Online generation is a separate test requiring your own provider configuration and an intentional service request; it may incur provider charges.

Mark an unperformed check **NOT_RUN**, or **BLOCKED** with its concrete reason (for example, no authorized separate Android profile, no second PDF editor, or provider quota). A build success, host callback or upload success does not replace those device observations.
