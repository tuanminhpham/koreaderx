describe("KOReaderX owned PDF highlights with real ReaderUI and MuPDF", function()
    local ReaderUI, Registry, DocSettings, UIManager, Screen, Transaction, Annotation, M, util, ffiUtil
    local directory, filename, reader
    setup(function()
        require("commonrequire"); disable_plugins()
        ReaderUI = require("apps/reader/readerui")
        Registry = require("document/documentregistry")
        DocSettings = require("docsettings")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Transaction = require("document/pdfannotationtransaction")
        Annotation = require("document/pdfannotations")
        M = require("ffi/mupdf")
        util = require("util")
        ffiUtil = require("ffi/util")
    end)
    local function openReader(write)
        reader = ReaderUI:new{ dimen = Screen:getSize(), document = Registry:openDocument(filename) }
        reader.document.configurable.text_wrap = 0
        reader.highlight.highlight_write_into_pdf = write
    end
    local function closeReader()
        reader:onClose(); reader = nil; UIManager:quit()
    end
    before_each(function()
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        DocSettings.setIsHashLocationEnabled(false)
        directory = os.tmpname(); os.remove(directory); util.makePath(directory)
        filename = directory .. "/owned.pdf"
        Transaction.copy("spec/front/unit/data/sample.pdf", filename)
        local settings = DocSettings:open(filename)
        settings:saveSetting("koreaderx_pdf_import", { version = 1, tombstones = {},
            seen_mtime = require("libs/libkoreader-lfs").attributes(filename, "modification") })
        settings:flush(); openReader(true)
    end)
    after_each(function()
        if reader then closeReader() end
        DocSettings:open(filename):purge()
        assert(ffiUtil.purgeDir(directory))
    end)
    local function point(page, word_index)
        local p = reader.document._document:openPage(page)
        local lines = p:getPageText(); p:close()
        for _, line in ipairs(lines) do
            if #line >= 3 then
                local word = line[word_index or 1]
                return {page=page, x=(word.x0+word.x1)/2, y=(word.y0+word.y1)/2, zoom=1, rotation=0}
            end
        end
        error("Fixture needs a line with at least three words")
    end
    local function selected(page, word_index)
        local pos = point(page, word_index)
        return reader.document:getTextFromPositions(pos, pos)
    end
    local function save(multi)
        local text = selected(10)
        if multi then
            text.pos1 = point(11)
            text.ext, text.pboxes, text.text = {}, nil, ""
            for page = 10, 11 do
                local part = reader.highlight:getExtendedHighlightPage(text.pos0, text.pos1, page)
                text.ext[page] = {pos0=part.pos0,pos1=part.pos1,pboxes=part.pboxes}
                text.text = text.text .. part.text
            end
        end
        text.drawer, text.color = "lighten", "green"
        reader.highlight.selected_text = text
        local index = reader.highlight:saveHighlight()
        assert.is_number(index)
        return index
    end
    local function entries(page)
        local p = reader.document._document:openPage(page or 10)
        local result = p:getEmbeddedAnnotations() or {}; p:close(); return result
    end
    local function diskCount(page)
        local d = M.openDocument(filename); local p = d:openPage(page or 10)
        local result = #(p:getEmbeddedAnnotations() or {}); p:close(); d:close(); return result
    end
    local function import()
        local count, skipped, invalid, conflicts = reader.highlight:importEmbeddedAnnotations(reader.document:getEmbeddedAnnotations() or {})
        assert.is_number(count)
        return count, skipped, invalid, conflicts
    end
    local function ownedIndex()
        for i, item in ipairs(reader.annotation.annotations) do if item.koreaderx_pdf_owned then return i end end
        error("Owned item missing")
    end
    local function addForeign()
        local boxes = selected(10).pboxes
        local p = reader.document._document:openPage(10)
        local part = p:createEmbeddedAnnotation{type=8,quads=Annotation.quads(boxes),color_n=3,
            color_components={0,2/3,0.4},author="Distinct foreign author",contents="Foreign note",flags=4,opacity=0.5}
        p:close(); reader.document.is_edited = true
        return part
    end
    it("does not import its own saved highlight after close/reopen, and preserves write-off behavior", function()
        reader.highlight.highlight_write_into_pdf = false
        local index = save()
        assert.equals(0, #reader.annotation.annotations[index].koreaderx_pdf_owned.parts)
        assert.equals(0, import()); assert.equals(0, #entries())
        reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:setHighlightColor(index, "green"))
        assert.is_nil(reader.annotation.annotations[index].koreaderx_pdf_source)
        assert.equals(0, import()); closeReader(); openReader(true)
        assert.equals(1, diskCount()); assert.equals(1, #reader.annotation.annotations)
        assert.equals(0, import()); assert.equals(0, import())
        closeReader(); openReader(false)
        assert.equals(1, #reader.annotation.annotations); assert.equals(0, import())
    end)
    it("keeps coincident foreign annotations through owned note, color, style, geometry and deletion", function()
        local foreign = addForeign(); save()
        assert.equals(1, import()); local index = ownedIndex()
        local item = reader.annotation.annotations[index]
        assert.is_true(reader.highlight:writePdfAnnotation("content", item, "Owned note")); item.note = "Owned note"
        assert.equals("Owned note", item.koreaderx_pdf_owned.parts[1].raw.contents)
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        local candidate = util.tableDeepCopy(reader.annotation.annotations[index]); candidate.drawer = "strikeout"
        assert.is_true(reader.highlight:commitOrdinaryChange(index, candidate))
        candidate = util.tableDeepCopy(reader.annotation.annotations[index])
        local span = reader.document:getTextFromPositions(point(10), point(10, 2))
        candidate.pos0, candidate.pos1, candidate.pboxes, candidate.text = span.pos0, span.pos1, span.pboxes, span.text
        assert.is_true(reader.highlight:commitOrdinaryChange(index, candidate))
        local p = reader.document._document:openPage(10)
        local pointer, retained = p:resolveEmbeddedAnnotation(foreign); p:close()
        assert.truthy(pointer); assert.are.same(foreign.raw, retained.raw)
        assert.equals(0, import()); index = ownedIndex()
        assert.is_true(reader.highlight:deleteHighlight(index))
        assert.equals(1, #entries()); assert.are.same(foreign.raw, entries()[1].raw)
        closeReader(); openReader(true)
        assert.equals(1, #reader.annotation.annotations); assert.equals(0, import())
    end)
    it("preserves native provenance across local-only edits and tombstones local-only deletion", function()
        save(); closeReader(); openReader(false)
        local index = ownedIndex(); local before = util.tableDeepCopy(reader.annotation.annotations[index].koreaderx_pdf_owned.parts)
        local hash = Transaction.hash(filename)
        assert.is_true(reader.highlight:setHighlightColor(index, "blue"))
        local item = reader.annotation.annotations[index]
        assert.is_true(reader.highlight:writePdfAnnotation("content", item, "Local only")); item.note = "Local only"
        assert.are.same(before, item.koreaderx_pdf_owned.parts)
        assert.equals(0, import()); index = ownedIndex()
        assert.is_true(reader.highlight:deleteHighlight(index)); assert.equals(1, #entries())
        assert.equals(0, import()); closeReader(); openReader(false)
        assert.equals(hash, Transaction.hash(filename)); assert.equals(0, #reader.annotation.annotations)
        assert.equals(0, import()); assert.equals(1, diskCount())
    end)
    it("collects every owned page and updates/deletes all parts without duplicates", function()
        local index = save(true)
        assert.equals(2, #reader.annotation.annotations[index].koreaderx_pdf_owned.parts)
        assert.equals(0, import()); index = ownedIndex()
        assert.is_true(reader.highlight:setHighlightColor(index, "blue"))
        local item = reader.annotation.annotations[index]
        assert.is_true(reader.highlight:writePdfAnnotation("content", item, "Both pages")); item.note = "Both pages"
        for _, part in ipairs(item.koreaderx_pdf_owned.parts) do assert.equals("Both pages", part.raw.contents) end
        closeReader(); openReader(true); assert.equals(0, import())
        assert.equals(1, diskCount(10)); assert.equals(1, diskCount(11))
        assert.is_true(reader.highlight:deleteHighlight(ownedIndex()))
        assert.equals(0, #entries(10)); assert.equals(0, #entries(11))
        closeReader(); openReader(true); assert.equals(0, import())
        assert.equals(0, diskCount(10)); assert.equals(0, diskCount(11))
    end)
    it("rejects a stale later page before touching the earlier native page or metadata", function()
        local index = save(true); local item = reader.annotation.annotations[index]
        local before = util.tableDeepCopy(item); local first = util.tableDeepCopy(entries(10))
        local p = reader.document._document:openPage(11)
        p:updateEmbeddedAnnotation(item.koreaderx_pdf_owned.parts[2], {contents="Changed externally"}); p:close()
        assert.is_false(reader.highlight:setHighlightColor(index, "purple"))
        assert.are.same(before, reader.annotation.annotations[index]); assert.are.same(first, entries(10))
        reader.document:discardChange() -- the deliberately altered native object cannot be published as owned
    end)
    it("rolls back a failed native multi-page candidate without losing pending prior writes", function()
        local index = save(true); local before = util.tableDeepCopy(reader.annotation.annotations)
        local first, second = util.tableDeepCopy(entries(10)), util.tableDeepCopy(entries(11))
        local save_native = reader.document.saveHighlight
        reader.document.saveHighlight = function(doc, page, item)
            if page == 11 then error("Injected failure after first-page native create") end
            return save_native(doc, page, item)
        end
        assert.is_false(reader.highlight:setHighlightColor(index, "purple"))
        reader.document.saveHighlight = nil
        assert.are.same(before, reader.annotation.annotations)
        assert.are.same(first, entries(10)); assert.are.same(second, entries(11))
        closeReader(); openReader(true)
        assert.equals(1, diskCount(10)); assert.equals(1, diskCount(11)); assert.equals(0, import())
    end)
    it("restores persisted ownership when on-to-off discards pending native writes", function()
        save(); reader:saveSettings(); reader.highlight.highlight_write_into_pdf = false
        closeReader(); openReader(false)
        assert.equals(0, diskCount()); assert.equals(0, #reader.annotation.annotations[1].koreaderx_pdf_owned.parts)
        assert.equals(0, import()); reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:setHighlightColor(1, "green")); closeReader(); openReader(true)
        local old = util.tableDeepCopy(reader.annotation.annotations[1].koreaderx_pdf_owned.parts)
        assert.is_true(reader.highlight:setHighlightColor(1, "blue")); reader:saveSettings()
        reader.highlight.highlight_write_into_pdf = false; closeReader(); openReader(false)
        assert.are.same(old, reader.annotation.annotations[1].koreaderx_pdf_owned.parts)
        assert.equals("blue", reader.annotation.annotations[1].color); assert.equals(0, import())
    end)
    it("recovers a flushed pending provenance record after native discard without a final metadata flush", function()
        save(); reader:saveSettings()
        reader.document:discardChange(); reader:closeDocument(); reader = nil; ReaderUI.instance = nil; UIManager:quit()
        openReader(false)
        assert.equals(0, diskCount()); assert.equals(0, #reader.annotation.annotations[1].koreaderx_pdf_owned.parts)
        assert.is_nil(reader.annotation.annotations[1].koreaderx_pdf_owned.pending)
        assert.equals(0, import())
    end)
    it("keeps the local item after delete-from-PDF and recreates owned identities on write-all", function()
        save(); closeReader(); openReader(true)
        local item = reader.annotation.annotations[1]
        assert.is_true(reader.highlight:writePdfAnnotation("delete", item)); assert.equals(0, #entries())
        assert.equals(1, #reader.annotation.annotations); assert.equals(0, #item.koreaderx_pdf_owned.parts)
        assert.is_true(reader.highlight:writePdfAnnotation("replace", item, nil, util.tableDeepCopy(item)))
        assert.equals(1, #entries()); assert.equals(0, import()); closeReader(); openReader(true)
        assert.equals(1, #reader.annotation.annotations); assert.equals(1, diskCount()); assert.equals(0, import())
    end)
    it("reports ambiguous legacy collisions instead of importing or deleting by geometry", function()
        save(); closeReader(); openReader(true)
        local item = reader.annotation.annotations[1]; item.koreaderx_pdf_owned = nil
        local before = util.tableDeepCopy(reader.annotation.annotations); local native = util.tableDeepCopy(entries())
        local count, _, _, conflicts = import()
        assert.equals(0, count); assert.equals(1, conflicts); assert.equals(1, #reader.annotation.annotations)
        assert.is_false(reader.highlight:setHighlightColor(1, "blue"))
        assert.are.same(before, reader.annotation.annotations); assert.are.same(native, entries())
        assert.is_false(reader.highlight:deleteHighlight(1)); assert.equals(1, #reader.annotation.annotations)
    end)
    it("blocks ordinary native mutation when the PDF changed outside the reader", function()
        save(); closeReader(); openReader(true)
        local before = util.tableDeepCopy(reader.annotation.annotations)
        local f = assert(io.open(filename, "ab")); f:write("\n% external test edit\n"); f:close()
        assert.is_false(reader.highlight:setHighlightColor(1, "blue"))
        assert.are.same(before, reader.annotation.annotations)
    end)
    it("uses native owned pages after an off-only local shrink for note, replacement and deletion", function()
        for _, action in ipairs({ "replace", "delete" }) do
            save(true); closeReader(); openReader(false); local index = ownedIndex()
            local item = reader.annotation.annotations[index]
            local candidate = util.tableDeepCopy(item)
            local one = selected(10)
            candidate.pos0, candidate.pos1, candidate.pboxes, candidate.text, candidate.ext = one.pos0, one.pos1, one.pboxes, one.text, nil
            assert.is_true(reader.highlight:commitOrdinaryChange(index, candidate))
            assert.equals(2, #item.koreaderx_pdf_owned.parts)
            reader.highlight.highlight_write_into_pdf = true
            assert.is_true(reader.highlight:writePdfAnnotation("content", item, "Native pages retained"))
            for _, part in ipairs(item.koreaderx_pdf_owned.parts) do assert.equals("Native pages retained", part.raw.contents) end
            if action == "replace" then
                assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
                assert.equals(1, #entries(10)); assert.equals(0, #entries(11))
                assert.equals(0, import()); assert.is_true(reader.highlight:deleteHighlight(ownedIndex()))
            else
                assert.is_true(reader.highlight:deleteHighlight(index))
            end
            assert.equals(0, #entries(10)); assert.equals(0, #entries(11))
            closeReader(); openReader(true); assert.equals(0, import())
        end
    end)
    it("cancels extension without mutation and commits/prepends a temporary owned selection that survives clear/reopen", function()
        local index = save(); local before = util.tableDeepCopy(reader.annotation.annotations)
        local native = util.tableDeepCopy(entries())
        reader.highlight:startSelection(index)
        reader.highlight.selected_text, reader.highlight.hold_pos = selected(11), point(11)
        reader.highlight:extendSelection()
        assert.are.same(before, reader.annotation.annotations); assert.are.same(native, entries())
        reader.highlight:clear(); reader.highlight.select_mode = false
        assert.are.same(before, reader.annotation.annotations)
        assert.is_true(reader.highlight:deleteHighlight(index))
        reader.highlight.selected_text = selected(11)
        reader.highlight:startSelection()
        assert.is_true(reader.annotation.annotations[reader.highlight.highlight_idx].is_tmp)
        reader.highlight.selected_text, reader.highlight.hold_pos = selected(10), point(10)
        reader.highlight:extendSelection()
        local committed = reader.highlight:saveHighlight()
        assert.is_number(committed)
        local item = reader.annotation.annotations[committed]
        assert.is_nil(item.is_tmp); assert.is_nil(item.is_extended)
        assert.equals(10, item.page); assert.equals(2, #item.koreaderx_pdf_owned.parts)
        reader.highlight:clear(); reader.highlight.select_mode = false
        assert.equals(1, #reader.annotation.annotations)
        closeReader(); openReader(true)
        assert.equals(1, #reader.annotation.annotations); assert.equals(0, import())
        assert.equals(1, diskCount(10)); assert.equals(1, diskCount(11))
    end)
    it("uses the actual bookmark note-delete and Add-note Cancel callbacks", function()
        local index = save(); local item = reader.annotation.annotations[index]
        assert.is_true(reader.highlight:writePdfAnnotation("content", item, "Remove me")); item.note = "Remove me"
        reader.bookmark:deleteItemNote(item)
        assert.is_nil(item.note); assert.is_nil(item.koreaderx_pdf_owned.parts[1].raw.contents)
        reader.bookmark:setBookmarkNote(index, true)
        UIManager:getTopmostVisibleWidget().buttons[1][1].callback()
        assert.equals(0, #reader.annotation.annotations); assert.equals(0, #entries())
        closeReader(); openReader(true); assert.equals(0, import()); assert.equals(0, diskCount())
    end)
    it("settles pending ordinary ownership when an imported transaction publishes the whole PDF", function()
        addForeign(); save(); assert.equals(1, import())
        local imported_index
        for i, item in ipairs(reader.annotation.annotations) do if item.koreaderx_pdf_source then imported_index = i end end
        assert.is_true(reader.highlight:setHighlightColor(imported_index, "purple"))
        local index = ownedIndex(); local owned = reader.annotation.annotations[index].koreaderx_pdf_owned
        assert.is_nil(owned.pending); local persisted = util.tableDeepCopy(owned.parts)
        assert.is_true(reader.highlight:setHighlightColor(index, "blue"))
        reader.highlight.highlight_write_into_pdf = false
        closeReader(); openReader(false)
        local restored = reader.annotation.annotations[ownedIndex()].koreaderx_pdf_owned.parts
        -- Sidecar dump/load rounds doubles; the serialized full source and
        -- exact native identity must still agree (not geometric ownership).
        assert.equals(Annotation.fingerprint(persisted), Annotation.fingerprint(restored))
        assert.has_no.errors(function() reader.document:validateOwnedAnnotation(reader.annotation.annotations[ownedIndex()]) end)
        assert.equals(2, #reader.annotation.annotations); assert.equals(0, import())
    end)
    it("publishes a verified snapshot without rewriting original bytes and recovers settings flushed before PDF save", function()
        local f = assert(io.open(filename, "rb")); local original = f:read("*a"); f:close()
        save(); reader:saveSettings(); reader.document:writeDocument()
        f = assert(io.open(filename, "rb")); local after = f:read("*a"); f:close()
        assert.equals(original, after:sub(1, #original))
        assert.is_true(#after < #original + 20000)
        reader:closeDocument(); reader = nil; ReaderUI.instance = nil; UIManager:quit(); openReader(true)
        assert.equals(1, diskCount()); assert.equals(1, #reader.annotation.annotations)
        assert.is_nil(reader.annotation.annotations[1].koreaderx_pdf_owned.pending); assert.equals(0, import())
    end)
    it("retains the original PDF when staging fails and can retry without duplicate ownership", function()
        save(); local hash = Transaction.hash(filename)
        local original_sync = Transaction.syncFile
        Transaction.syncFile = function() error("Injected staged fsync failure before publication") end
        local ok = pcall(reader.document.writeDocument, reader.document)
        Transaction.syncFile = original_sync
        assert.is_false(ok); assert.equals(hash, Transaction.hash(filename))
        assert.truthy(reader.annotation.annotations[1].koreaderx_pdf_owned.pending)
        reader.document:writeDocument(); closeReader(); openReader(true)
        assert.equals(1, diskCount()); assert.equals(0, import())
    end)
    it("blocks owned changes when the loaded sidecar changed externally", function()
        save(); closeReader(); openReader(true)
        local before = util.tableDeepCopy(reader.annotation.annotations); local native = util.tableDeepCopy(entries())
        local f = assert(io.open(Transaction.metadataPath(reader.doc_settings), "ab")); f:write("\n-- external edit\n"); f:close()
        assert.is_false(reader.highlight:setHighlightColor(1, "purple"))
        assert.are.same(before, reader.annotation.annotations); assert.are.same(native, entries())
    end)
    it("opens unknown or malformed pending ownership without adopting or crashing", function()
        save(); closeReader(); openReader(true)
        local item = reader.annotation.annotations[1]
        item.koreaderx_pdf_owned = {version=2,parts={},pending={before_hash="unknown",parts={}}}
        local future = util.tableDeepCopy(item.koreaderx_pdf_owned)
        reader.document:reconcileOwnedProvenance(reader.annotation.annotations)
        assert.are.same(future, item.koreaderx_pdf_owned)
        item.koreaderx_pdf_owned = {version=1,parts={{page=9999}},pending={before_hash="unknown",parts={{page=9999}}}}
        assert.has_no.errors(function() reader.document:reconcileOwnedProvenance(reader.annotation.annotations) end)
        assert.is_false(reader.highlight:setHighlightColor(1, "purple"))
        reader.document:discardChange()
    end)

    it("recovers a flushed pending native deletion from its atomic publication receipt", function()
        save(); closeReader(); openReader(true)
        local item = reader.annotation.annotations[1]
        assert.is_true(reader.highlight:writePdfAnnotation("delete", item))
        reader:saveSettings(); reader.document:writeDocument()
        reader:closeDocument(); reader = nil; ReaderUI.instance = nil; UIManager:quit(); openReader(true)
        item = reader.annotation.annotations[1]
        assert.equals(0, diskCount()); assert.equals(0, #item.koreaderx_pdf_owned.parts)
        assert.is_nil(item.koreaderx_pdf_owned.pending)
        assert.is_true(reader.highlight:setHighlightColor(1, "purple"))
        reader.highlight.highlight_write_into_pdf = false
        closeReader(); openReader(false)
        assert.equals(0, #reader.annotation.annotations[1].koreaderx_pdf_owned.parts)
        assert.equals(0, diskCount()); assert.equals(0, import())
    end)

    it("does not relocate a missing owned tombstone onto a coincident foreign annotation", function()
        save(); closeReader(); openReader(false)
        local part = util.tableDeepCopy(reader.annotation.annotations[1].koreaderx_pdf_owned.parts[1])
        assert.is_true(reader.highlight:deleteHighlight(1))
        local p = reader.document._document:openPage(10)
        p:deleteEmbeddedAnnotation(part, true)
        local foreign = p:createEmbeddedAnnotation(part.raw)
        p:close()
        assert.is_not.equals(part.num, foreign.num)
        local added, skipped, _, conflicts = import()
        assert.equals(0, added); assert.equals(0, skipped); assert.equals(1, conflicts)
        assert.equals(1, #entries())
        assert.equals(Annotation.fingerprint(part.raw), Annotation.fingerprint(entries()[1].raw))
        assert.equals(foreign.num, entries()[1].source.num)
        reader.document:discardChange()
    end)

    it("keeps an EPUB highlight intact after boundary adjustment and close/reopen", function()
        closeReader(); DocSettings:open(filename):purge(); os.remove(filename)
        filename = directory .. "/owned.epub"
        Transaction.copy("spec/front/unit/data/juliet.epub", filename)
        reader = ReaderUI:new{dimen=Screen:getSize(),document=Registry:openDocument(filename),_testsuite=true}
        reader.highlight.highlight_write_into_pdf = false
        reader.rolling:onGotoPage(10); UIManager:show(reader)
        reader.highlight:onHold(nil, {pos=require("ui/geometry"):new{x=400,y=70}})
        local index = assert(reader.highlight:saveHighlight())
        reader.highlight:clear()
        local item = reader.annotation.annotations[index]
        local old_text, old_end = item.text, item.pos1
        assert.is_true(reader.highlight:updateHighlight(index, 1, 1))
        assert.equals(item, reader.annotation.annotations[index])
        assert.is_not.equals(old_text, item.text); assert.is_not.equals(old_end, item.pos1)
        assert.is_string(item.pos0); assert.is_string(item.pos1); assert.truthy(item.drawer)
        local text = item.text
        closeReader()
        reader = ReaderUI:new{dimen=Screen:getSize(),document=Registry:openDocument(filename),_testsuite=true}
        assert.equals(1, #reader.annotation.annotations); assert.equals(text, reader.annotation.annotations[1].text)
    end)

    it("does not settle unresolved empty ownership during unrelated PDF publication", function()
        save(); closeReader(); openReader(true)
        local item = reader.annotation.annotations[1]
        local original = util.tableDeepCopy(item.koreaderx_pdf_owned)
        item.koreaderx_pdf_owned = {version=1,parts={},pending={before_hash="unknown",parts={},unresolved=true}}
        local before = util.tableDeepCopy(item.koreaderx_pdf_owned)
        local hash = Transaction.hash(filename)
        assert.has.errors(function() reader.document:writeDocument() end)
        assert.equals(hash, Transaction.hash(filename)); assert.are.same(before, item.koreaderx_pdf_owned)
        reader.document:discardChange()
        assert.are.same(before, item.koreaderx_pdf_owned)
        item.koreaderx_pdf_owned = original
    end)

    it("blocks pending ordinary publication after a late external sidecar edit", function()
        save(); local before = util.tableDeepCopy(reader.annotation.annotations)
        local hash = Transaction.hash(filename)
        local f = assert(io.open(Transaction.metadataPath(reader.doc_settings), "ab")); f:write("\n-- late external edit\n"); f:close()
        assert.has.errors(function() reader.document:writeDocument() end)
        assert.equals(hash, Transaction.hash(filename)); assert.are.same(before, reader.annotation.annotations)
        reader.document:discardChange()
    end)

    it("rechecks metadata immediately before publishing after an edit during staging", function()
        save(); local hash = Transaction.hash(filename)
        local original_sync = Transaction.syncFile
        Transaction.syncFile = function(path)
            original_sync(path)
            local f = assert(io.open(Transaction.metadataPath(reader.doc_settings), "ab"))
            f:write("\n-- external edit during PDF staging\n"); f:close()
        end
        local ok = pcall(reader.document.writeDocument, reader.document)
        Transaction.syncFile = original_sync
        assert.is_false(ok); assert.equals(hash, Transaction.hash(filename))
        assert.truthy(reader.annotation.annotations[1].koreaderx_pdf_owned.pending)
        reader.document:discardChange()
    end)

    it("retains ordinary PDF ownership across mixed-source bulk writes and repeated reopen", function()
        -- Put an ordinary local highlight between imported items in reading
        -- order. Imported commits replace the live annotations table, so the
        -- bulk command must obtain the current item before each operation.
        for _, page_number in ipairs({10, 11, 12}) do
            local page = reader.document._document:openPage(page_number)
            page:createEmbeddedAnnotation{
                type = 8, quads = Annotation.quads(selected(page_number).pboxes),
                color_n = 3, color_components = {1, 1, 0},
                author = "Bulk fixture", contents = "Imported page " .. page_number,
            }
            page:close()
        end
        reader.document.is_edited = true
        reader.highlight.highlight_write_into_pdf = false
        assert.equals(3, import())
        local text = selected(10, 2)
        text.drawer, text.color, text.note = "lighten", "cyan", "Bulk local note"
        reader.highlight.selected_text = text
        assert.is_number(reader.highlight:saveHighlight())
        assert.equals(4, #reader.annotation.annotations)
        assert.truthy(reader.annotation.annotations[1].koreaderx_pdf_source)
        assert.equals(2, ownedIndex())
        assert.truthy(reader.annotation.annotations[3].koreaderx_pdf_source)
        assert.equals(0, #reader.annotation.annotations[ownedIndex()].koreaderx_pdf_owned.parts)
        reader.highlight.highlight_write_into_pdf = true

        local function writeAllFromRegisteredMenu()
            local menu_items = {}
            reader.highlight:addToMainMenu(menu_items)
            local command
            for _, item in ipairs(menu_items.highlight_options.sub_item_table) do
                for _, sub_item in ipairs(item.sub_item_table or {}) do
                    if sub_item.text == "Write all highlights into PDF file" then command = sub_item end
                end
            end
            assert.truthy(command)
            assert.is_true(command.enabled_func())
            command.callback()
            local confirmation = UIManager:getTopmostVisibleWidget()
            assert.equals("Are you sure you want to write all KOReader highlights into PDF file?", confirmation.text)
            confirmation.ok_callback()
            UIManager:close(confirmation)
        end
        for _ = 1, 3 do
            writeAllFromRegisteredMenu()
            local item = reader.annotation.annotations[ownedIndex()]
            assert.equals(1, #item.koreaderx_pdf_owned.parts)
            assert.equals("Bulk local note", item.koreaderx_pdf_owned.parts[1].raw.contents)
            assert.equals("cyan", item.color)
            closeReader()
            assert.equals(2, diskCount(10))
            assert.equals(1, diskCount(11))
            assert.equals(1, diskCount(12))
            openReader(true)
            assert.equals(4, #reader.annotation.annotations)
            assert.equals(1, #reader.annotation.annotations[ownedIndex()].koreaderx_pdf_owned.parts)
            assert.equals(0, import())
            local seen = {}
            for _, page_number in ipairs({10, 11, 12}) do
                for _, entry in ipairs(entries(page_number)) do
                    local note = entry.raw.contents
                    assert.is_nil(seen[note])
                    seen[note] = true
                end
            end
            assert.truthy(seen["Bulk local note"])
            for _, page_number in ipairs({10, 11, 12}) do
                assert.truthy(seen["Imported page " .. page_number])
            end
        end
    end)

end)
