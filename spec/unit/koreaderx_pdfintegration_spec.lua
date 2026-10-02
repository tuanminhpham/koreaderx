describe("KOReaderX imported annotations with real MuPDF and ReaderUI", function()
    local ReaderUI, Registry, DocSettings, UIManager, Screen, Transaction, Annotation, util, ffiUtil
    local directory, filename, reader
    setup(function()
        require("commonrequire")
        disable_plugins()
        ReaderUI = require("apps/reader/readerui")
        Registry = require("document/documentregistry")
        DocSettings = require("docsettings")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Transaction = require("document/pdfannotationtransaction")
        Annotation = require("document/pdfannotations")
        util = require("util")
        ffiUtil = require("ffi/util")
    end)
    local function openReader()
        reader = ReaderUI:new{ dimen = Screen:getSize(), document = Registry:openDocument(filename) }
        reader.highlight.highlight_write_into_pdf = false
    end
    local function sourceEntries()
        local native = require("ffi/mupdf").openDocument(filename)
        local page = native:openPage(1)
        local entries = page:getEmbeddedAnnotations() or {}
        page:close(); native:close()
        return entries
    end
    local function importedIndex(note)
        for index, item in ipairs(reader.annotation.annotations) do
            if item.note == note and item.koreaderx_pdf_source then return index end
        end
        error("Imported item not found")
    end
    before_each(function()
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        DocSettings.setIsHashLocationEnabled(false)
        directory = os.tmpname(); os.remove(directory); util.makePath(directory)
        filename = directory .. "/annotations.pdf"
        Transaction.copy("spec/front/unit/data/sample.pdf", filename)
        local native = require("ffi/mupdf").openDocument(filename)
        local page = native:openPage(1)
        -- sample.pdf page 1 is a cover without a text layer: import must preserve its note.
        local word = {x0 = 30, y0 = 30, x1 = 100, y1 = 45}
        local raw = { type = 8, color_n = 3, color_components = {1, 1, 0},
            quads = {{word.x0, word.y0, word.x1, word.y0, word.x0, word.y1, word.x1, word.y1}},
            author = "Tác giả", contents = "first source", flags = 4, opacity = 0.5 }
        page:createEmbeddedAnnotation(raw)
        raw.contents = "coincident source"
        raw.color_components = {0, 1, 0}
        page:createEmbeddedAnnotation(raw)
        page:close(); native:writeDocument(filename); native:close()
        local settings = DocSettings:open(filename)
        settings:saveSetting("koreaderx_pdf_import", { version = 1, tombstones = {},
            seen_mtime = require("libs/libkoreader-lfs").attributes(filename, "modification") })
        settings:flush()
        openReader()
    end)
    after_each(function()
        if reader then reader:onClose(); reader = nil end
        UIManager:quit()
        DocSettings:open(filename):purge()
        assert(ffiUtil.purgeDir(directory))
    end)
    local function doImport()
        local annotations = reader.document:getEmbeddedAnnotations()
        local count, err = reader.highlight:importEmbeddedAnnotations(annotations)
        assert.truthy(count, err)
        return count
    end
    it("imports without changing PDF bytes, keeps local items and repeats idempotently", function()
        local before = Transaction.hash(filename)
        reader.annotation:addItem{ page = 2, text = "page bookmark" }
        assert.equals(2, doImport())
        assert.equals("", reader.annotation.annotations[importedIndex("first source")].text)
        assert.equals(3, #reader.annotation.annotations)
        assert.equals(0, doImport())
        assert.equals(before, Transaction.hash(filename))
        assert.equals(2, #sourceEntries())
        reader:onClose(); reader = nil
        assert.equals(before, Transaction.hash(filename))
        openReader()
        assert.equals(3, #reader.annotation.annotations)
        assert.equals(0, doImport())
        assert.equals("Tác giả", reader.annotation.annotations[importedIndex("first source")].author)
    end)
    it("registers the original hold and tap touch zones alongside PDF import readiness", function()
        reader.highlight:onReaderReady()
        assert.truthy(reader._zones.readerhighlight_hold)
        assert.truthy(reader._zones.readerhighlight_hold_pan)
        assert.truthy(reader._zones.readerhighlight_hold_release)
    end)
    it("keeps a palette bound to an imported item across repeated transaction table swaps", function()
        doImport()
        local index = importedIndex("first source")
        UIManager:show(reader)
        reader.highlight:showHighlightDialog(index)
        local widget = UIManager:getTopmostVisibleWidget()
        widget:paintTo(Screen.bb, 0, 0)
        for _, color in ipairs({ {2, "green"}, {4, "purple"} }) do
            widget.buttontable.buttons_layout[1][color[1]]:onTapSelectButton()
            assert.equals(color[2], reader.annotation.annotations[index].color)
            assert.equals(widget, UIManager:getTopmostVisibleWidget())
        end
        widget.buttontable.buttons_layout[2][1]:onTapSelectButton()
        assert.equals(1, #reader.annotation.annotations)
        assert.equals("coincident source", reader.annotation.annotations[1].note)
    end)
    it("deletes an imported note from the note dialog without losing the source snapshot", function()
        doImport()
        local index = importedIndex("first source")
        reader.highlight.highlight_write_into_pdf = true
        reader.highlight:showHighlightNoteOrDialog(index)
        local viewer = UIManager:getTopmostVisibleWidget()
        viewer.buttons_table[1][1].callback()
        assert.is_nil(reader.annotation.annotations[index].note)
        assert.is_nil(sourceEntries()[1].contents)
        assert.equals("Tác giả", sourceEntries()[1].author)
    end)
    it("keeps native pixels and hit targets without adding a second highlight layer", function()
        local function nativePixels()
            local page = reader.document._document:openPage(1)
            local dc = require("ffi/drawcontext").new()
            local width, height = page:getSize(dc)
            local bb = page:draw_new(dc, math.ceil(width), math.ceil(height), 0, 0)
            local bytes = require("ffi").string(bb.data, bb.stride * bb.h)
            bb:free(); page:close()
            return bytes
        end
        local before = nativePixels()
        doImport()
        assert.equals(before, nativePixels())
        UIManager:show(reader)
        reader.view.highlight.note_mark = nil
        local bb = Screen.bb:copy()
        local pixels = require("ffi").string(bb.data, bb.stride * bb.h)
        reader.view:drawSavedHighlight(bb, 0, 0)
        assert.is_true(#reader.view.highlight.visible_boxes > 0)
        assert.equals(pixels, require("ffi").string(bb.data, bb.stride * bb.h))
        bb:free()
        local index = importedIndex("first source")
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        assert.is_not.equals(before, nativePixels()) -- original is selectively suppressed
    end)
    it("keeps annotations discoverable after a hash-sidecar PDF rewrite and fresh lookup", function()
        reader:onClose(); reader = nil
        G_reader_settings:saveSetting("document_metadata_folder", "hash")
        DocSettings.setIsHashLocationEnabled(true)
        local settings = DocSettings:open(filename)
        settings:flush()
        openReader()
        doImport()
        local index = importedIndex("first source")
        local old_dir = reader.doc_settings:getSidecarDir(filename, "hash")
        Transaction.writeTable(old_dir .. "/custom_metadata.lua", {title = "Custom title"})
        reader.doc_settings:getCustomMetadataFile(true)
        reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        local new_dir = reader.doc_settings.hash_sidecar_dir
        assert.is_not.equals(old_dir, new_dir)
        reader:onClose(); reader = nil
        DocSettings.invalidateDocumentHash(filename) -- equivalent to a fresh process cache
        local fresh = DocSettings:open(filename)
        assert.equals(new_dir .. "/" .. fresh.sidecar_filename, fresh.source_candidate)
        assert.equals("purple", fresh:readSetting("annotations")[index].color)
        assert.equals("Custom title", Transaction.readTable(new_dir .. "/custom_metadata.lua").title)
        assert.truthy(require("libs/libkoreader-lfs").attributes(old_dir)) -- rollback snapshot kept
    end)
    it("keeps color changes local and returns the original after metadata deletion", function()
        doImport()
        local before = Transaction.hash(filename)
        local index = importedIndex("first source")
        local item = reader.annotation.annotations[index]
        assert.equals("native", reader.document:importedAnnotationState(item, 1))
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        item = reader.annotation.annotations[index]
        assert.equals("override", reader.document:importedAnnotationState(item, 1))
        local revision = reader.document.koreaderx_render_revision[1]
        assert.is_true(reader.highlight:setHighlightColor(index, "cyan"))
        assert.is_not.equals(revision, reader.document.koreaderx_render_revision[1])
        assert.equals(before, Transaction.hash(filename))
        assert.is_true(reader.highlight:deleteHighlight(index))
        assert.equals(before, Transaction.hash(filename))
        assert.equals(2, #sourceEntries())
        assert.equals(0, doImport())
        assert.equals(1, #reader.annotation.annotations)
        assert.is_nil(reader.document._document.annotation_render_filter[1])
    end)
    it("updates only the identified coincident original with write enabled", function()
        doImport()
        local index = importedIndex("first source")
        local old = util.tableDeepCopy(reader.annotation.annotations[index].koreaderx_pdf_source.parts[1])
        reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        local item = reader.annotation.annotations[index]
        assert.equals("native", reader.document:importedAnnotationState(item, 1))
        assert.equals(old.num, item.koreaderx_pdf_source.parts[1].num)
        local entries = sourceEntries()
        assert.equals(2, #entries)
        assert.equals("Tác giả", entries[1].author)
        assert.equals(old.raw.opacity, entries[1].raw.opacity)
        assert.equals("coincident source", entries[2].contents)
        assert.same({0, 1, 0}, entries[2].color_components)
        assert.is_true(reader.highlight:writePdfAnnotation("content", item, "edited note"))
        assert.equals("edited note", sourceEntries()[1].contents)
        assert.is_true(reader.highlight:deleteHighlight(index))
        assert.equals(1, #sourceEntries())
        assert.equals("coincident source", sourceEntries()[1].contents)
    end)
    it("removes an imported original from PDF while keeping its KOReader highlight", function()
        doImport()
        local index = importedIndex("first source")
        reader.highlight.highlight_write_into_pdf = true
        local candidate = util.tableDeepCopy(reader.annotation.annotations[index])
        assert.is_true(reader.highlight:commitImportedChange(index, candidate, "detach"))
        assert.equals(2, #reader.annotation.annotations)
        assert.equals("first source", reader.annotation.annotations[index].note)
        assert.is_nil(reader.annotation.annotations[index].koreaderx_pdf_source)
        assert.equals(1, #sourceEntries())
        assert.equals("coincident source", sourceEntries()[1].contents)
        assert.equals(0, doImport())
        assert.equals(2, #reader.annotation.annotations)
    end)
    it("applies bulk appearance through the real menu with local and PDF write modes", function()
        doImport()
        local before = Transaction.hash(filename)
        local function applyMenu()
            local menu = {}
            reader.highlight:addToMainMenu(menu)
            for _, item in ipairs(menu.highlight_options.sub_item_table) do
                if item.text == "Apply current style and color to all highlights" then
                    item.callback()
                    UIManager:getTopmostVisibleWidget().ok_callback()
                    return
                end
            end
            error("Bulk appearance menu missing")
        end
        reader.view.highlight.saved_drawer, reader.view.highlight.saved_color = "strikeout", "purple"
        applyMenu()
        for _, item in ipairs(reader.annotation.annotations) do
            assert.equals("purple", item.color)
            assert.equals("strikeout", item.drawer)
            assert.equals("override", reader.document:importedAnnotationState(item, 1))
        end
        assert.equals(before, Transaction.hash(filename))
        reader.highlight.highlight_write_into_pdf = true
        applyMenu()
        for _, item in ipairs(reader.annotation.annotations) do
            assert.equals("native", reader.document:importedAnnotationState(item, 1))
            assert.equals(11, item.koreaderx_pdf_source.parts[1].raw.type)
        end
        local index = importedIndex("first source")
        reader.annotation.annotations[index].koreaderx_pdf_source.parts[1].raw.contents = "stale metadata"
        local unchanged = Annotation.fingerprint(reader.annotation.annotations)
        local unchanged_pdf = Transaction.hash(filename)
        reader.view.highlight.saved_color = "cyan"
        assert.equals(0, reader.highlight:applyCurrentHighlightStyleAndColor())
        assert.equals(unchanged, Annotation.fingerprint(reader.annotation.annotations))
        assert.equals(unchanged_pdf, Transaction.hash(filename))
    end)
    it("preserves non-axis raw quads during all-save without a geometry edit", function()
        local page = reader.document._document:openPage(1)
        local quad = {20, 50, 90, 55, 15, 65, 85, 70}
        page:createEmbeddedAnnotation{type = 8, color_n = 3, color_components = {1, 1, 0},
            quads = {quad}, contents = "skewed source"}
        page:close()
        reader.document.is_edited = true
        doImport()
        local index = importedIndex("skewed source")
        reader.highlight.highlight_write_into_pdf = true
        local candidate = util.tableDeepCopy(reader.annotation.annotations[index])
        assert.is_true(reader.highlight:commitImportedChange(index, candidate, "all"))
        assert.same({quad}, reader.annotation.annotations[index].koreaderx_pdf_source.parts[1].raw.quads)
    end)
    it("stages multi-page geometry and preserves author/note when extending and shrinking", function()
        doImport()
        local index = importedIndex("first source")
        local item = util.tableDeepCopy(reader.annotation.annotations[index])
        local boxes = util.tableDeepCopy(item.pboxes)
        local pos0, pos1 = util.tableDeepCopy(item.pos0), util.tableDeepCopy(item.pos1)
        local end0, end1 = util.tableDeepCopy(pos0), util.tableDeepCopy(pos1)
        end0.page, end1.page = 2, 2
        item.ext = {[1] = {pos0 = pos0, pos1 = pos1, pboxes = boxes},
            [2] = {pos0 = end0, pos1 = end1, pboxes = util.tableDeepCopy(boxes)}}
        item.pos1 = end1
        reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:commitImportedChange(index, item, "geometry"))
        item = reader.annotation.annotations[index]
        assert.equals(2, #item.koreaderx_pdf_source.parts)
        assert.equals("Tác giả", item.koreaderx_pdf_source.parts[2].raw.author)
        assert.equals("first source", item.koreaderx_pdf_source.parts[2].raw.contents)
        local candidate = util.tableDeepCopy(item)
        candidate.pos1, candidate.pboxes, candidate.ext = pos1, boxes, nil
        assert.is_true(reader.highlight:commitImportedChange(index, candidate, "geometry"))
        assert.equals(1, #reader.annotation.annotations[index].koreaderx_pdf_source.parts)
        local native = require("ffi/mupdf").openDocument(filename)
        local page = native:openPage(2)
        assert.is_nil(page:getEmbeddedAnnotations())
        page:close(); native:close()
    end)
    it("writes effective local style, color and note to every page during explicit bulk save", function()
        doImport()
        local index = importedIndex("first source")
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        local candidate = util.tableDeepCopy(reader.annotation.annotations[index])
        candidate.drawer = "strikeout"
        assert.is_true(reader.highlight:commitImportedChange(index, candidate, "style"))
        assert.is_true(reader.highlight:writePdfAnnotation("content", reader.annotation.annotations[index], "local note"))
        candidate = util.tableDeepCopy(reader.annotation.annotations[index])
        local p0, p1 = util.tableDeepCopy(candidate.pos0), util.tableDeepCopy(candidate.pos1)
        local e0, e1 = util.tableDeepCopy(p0), util.tableDeepCopy(p1)
        e0.page, e1.page = 2, 2
        candidate.ext = {[1] = {pos0 = p0, pos1 = p1, pboxes = candidate.pboxes},
            [2] = {pos0 = e0, pos1 = e1, pboxes = util.tableDeepCopy(candidate.pboxes)}}
        candidate.pos1 = e1
        assert.is_true(reader.highlight:commitImportedChange(index, candidate, "geometry"))
        reader.highlight.highlight_write_into_pdf = true
        candidate = util.tableDeepCopy(reader.annotation.annotations[index])
        assert.is_true(reader.highlight:commitImportedChange(index, candidate, "all"))
        local parts = reader.annotation.annotations[index].koreaderx_pdf_source.parts
        assert.equals(2, #parts)
        for _, part in ipairs(parts) do
            assert.equals(11, part.raw.type)
            assert.equals("local note", part.raw.contents)
            assert.equals("Tác giả", part.raw.author)
            assert.same(parts[1].raw.color_components, part.raw.color_components)
        end
        assert.equals(require("libs/libkoreader-lfs").attributes(filename, "modification"),
            reader.doc_settings:readSetting("koreaderx_pdf_import").seen_mtime)
    end)
    it("adjusts imported boundaries with margins using actual page text", function()
        local page = reader.document._document:openPage(10)
        local line
        for _, candidate in ipairs(page:getPageText()) do
            if #candidate >= 4 then line = candidate; break end
        end
        assert.truthy(line)
        local a, b = line[2], line[3]
        page:createEmbeddedAnnotation{type = 8, color_n = 3, color_components = {1, 1, 0},
            quads = {{a.x0 - 0.2, a.y0 - 1, b.x1 + 0.2, b.y0 - 1,
                a.x0 - 0.2, a.y1 + 1, b.x1 + 0.2, b.y1 + 1}}, contents = "boundary source", author = "boundary author"}
        page:close()
        reader.document.is_edited = true
        doImport()
        local index = importedIndex("boundary source")
        local original = util.tableDeepCopy(reader.annotation.annotations[index])
        reader.paging:onGotoPage(10)
        reader.highlight:updateHighlight(index, 0, -1)
        local changed = reader.annotation.annotations[index]
        assert.is_true(changed.pos0.x < original.pos0.x)
        assert.same(original.koreaderx_pdf_source, changed.koreaderx_pdf_source)
        reader.highlight.highlight_write_into_pdf = true
        reader.highlight:updateHighlight(index, 1, 1)
        changed = reader.annotation.annotations[index]
        assert.is_true(changed.pos1.x > original.pos1.x)
        assert.equals("boundary author", changed.koreaderx_pdf_source.parts[1].raw.author)
    end)
    it("preserves pending ordinary highlights when committing an imported edit", function()
        doImport()
        local index = importedIndex("first source")
        local pending = {pboxes = {{x = 20, y = 200, w = 70, h = 15}}, color = "cyan", drawer = "lighten"}
        reader.document:saveHighlight(1, pending)
        assert.equals(2, #sourceEntries()) -- still only in the live native handle
        reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        assert.equals(3, #sourceEntries())
        assert.is_false(reader.document.is_edited)
    end)
    it("recovers a failed second rename before reporting a native edit successful", function()
        doImport()
        local index = importedIndex("first source")
        reader.highlight.highlight_write_into_pdf = true
        local metadata_path = Transaction.metadataPath(reader.doc_settings)
        local real_rename = os.rename
        local failed = false
        local renamed = stub(os, "rename", function(from, to)
            if to == metadata_path and not failed then failed = true; return nil, "injected second rename failure" end
            return real_rename(from, to)
        end)
        local ok, changed = pcall(reader.highlight.setHighlightColor, reader.highlight, index, "purple")
        renamed:revert()
        assert.is_true(ok)
        assert.is_true(changed)
        assert.is_true(failed)
        assert.is_nil(reader.doc_settings.koreaderx_transaction_blocked)
        assert.equals("purple", Transaction.readTable(metadata_path).annotations[index].color)
        assert.equals("purple", reader.annotation.annotations[index].color)
        assert.is_false(Transaction.recover(filename))
    end)
    it("blocks autosave and export after an unrecoverable metadata hash conflict", function()
        doImport()
        local index = importedIndex("first source")
        reader.highlight.highlight_write_into_pdf = true
        local metadata_path = Transaction.metadataPath(reader.doc_settings)
        local real_rename = os.rename
        local renamed = stub(os, "rename", function(from, to)
            if to == metadata_path then
                Transaction.writeTable(metadata_path, { annotations = {}, external = "changed during transaction" })
                return nil, "injected external metadata edit"
            end
            return real_rename(from, to)
        end)
        local ok, changed = pcall(reader.highlight.setHighlightColor, reader.highlight, index, "purple")
        renamed:revert()
        assert.is_true(ok)
        assert.is_false(changed)
        assert.is_true(reader.doc_settings.koreaderx_transaction_blocked)
        local pdf_hash, metadata_hash = Transaction.hash(filename), Transaction.hash(metadata_path)
        local old_annotations = Annotation.fingerprint(reader.annotation.annotations)
        reader.highlight.highlight_write_into_pdf = false
        assert.is_false(reader.highlight:setHighlightColor(index, "cyan"))
        assert.is_false(reader.highlight:deleteHighlight(index))
        assert.equals(0, reader.highlight:applyCurrentHighlightStyleAndColor())
        assert.is_nil(reader.highlight:importEmbeddedAnnotations({}))
        assert.has_error(function() Transaction.commitMetadata(reader.doc_settings, {}) end)
        assert.has_error(function() reader.document:writeDocument() end)
        assert.is_false(reader.document:saveHighlight(1, {pboxes = {{x = 1,y = 1,w = 2,h = 2}}}))
        local incoming_path = reader.annotation:getExportAnnotationsFilepath()
        Transaction.writeTable(incoming_path, { device_id = "different device", paging = true,
            datetime = "2099-01-01 00:00:00", annotations = {} })
        local incoming_hash = Transaction.hash(incoming_path)
        assert.is_nil(reader.annotation:importAnnotations())
        assert.equals(incoming_hash, Transaction.hash(incoming_path))
        os.remove(incoming_path)
        assert.equals(old_annotations, Annotation.fingerprint(reader.annotation.annotations))
        assert.equals(pdf_hash, Transaction.hash(filename))
        assert.equals(metadata_hash, Transaction.hash(metadata_path))
        reader:onClose(); reader = nil
        assert.equals(pdf_hash, Transaction.hash(filename))
        assert.equals(metadata_hash, Transaction.hash(metadata_path))
        assert.has_error(function() Transaction.recover(filename) end)
    end)
    it("rejects external sidecar edits made before a local or native annotation change", function()
        doImport()
        local index = importedIndex("first source")
        local path = Transaction.metadataPath(reader.doc_settings)
        local external = Transaction.readTable(path)
        external.external = "sync tool update before editing"
        Transaction.writeTable(path, external)
        local before_pdf, before_sidecar = Transaction.hash(filename), Transaction.hash(path)
        local before_items = Annotation.fingerprint(reader.annotation.annotations)
        assert.is_false(reader.highlight:setHighlightColor(index, "cyan"))
        reader.highlight.highlight_write_into_pdf = true
        assert.is_false(reader.highlight:setHighlightColor(index, "purple"))
        assert.is_true(reader.doc_settings.koreaderx_transaction_blocked)
        assert.equals(before_items, Annotation.fingerprint(reader.annotation.annotations))
        reader:onClose(); reader = nil
        assert.equals(before_pdf, Transaction.hash(filename))
        assert.equals(before_sidecar, Transaction.hash(path))
    end)
    it("does not recreate a sidecar removed externally while the book is open", function()
        doImport()
        local index = importedIndex("first source")
        local path = Transaction.metadataPath(reader.doc_settings)
        assert(os.remove(path))
        assert.is_false(reader.highlight:setHighlightColor(index, "cyan"))
        reader:onClose(); reader = nil
        assert.equals("absent", Transaction.hash(path))
    end)
    it("does not create a hash sidecar directory merely to observe metadata on open", function()
        reader:onClose(); reader = nil
        G_reader_settings:saveSetting("document_metadata_folder", "hash")
        DocSettings.setIsHashLocationEnabled(true)
        -- Earlier rollback tests retain old hash directories. Use distinct PDF
        -- bytes here, rather than assuming another document's hash is absent.
        local unique = directory .. "/readonly-probe.pdf"
        local native = require("ffi/mupdf").openDocument(filename)
        local page = native:openPage(1)
        page:createEmbeddedAnnotation{type = 8, color_n = 3, color_components = {1, 1, 0},
            quads = {{10, 10, 30, 10, 10, 20, 30, 20}}, contents = "readonly " .. directory}
        page:close(); native:writeDocument(unique); native:close()
        local path = DocSettings:getSidecarDir(unique, "hash")
        assert.is_nil(require("libs/libkoreader-lfs").attributes(path))
        local settings = DocSettings:open(unique)
        assert.is_nil(settings.koreaderx_transaction_blocked)
        assert.is_nil(require("libs/libkoreader-lfs").attributes(path))
    end)
    it("refreshes sidecar baseline after ordinary flush and successive imported edits", function()
        doImport()
        reader.doc_settings:saveSetting("unrelated_reader_setting", "retained")
        assert.truthy(reader.doc_settings:flush())
        local index = importedIndex("first source")
        assert.is_true(reader.highlight:setHighlightColor(index, "cyan"))
        reader.highlight.highlight_write_into_pdf = true
        assert.is_true(reader.highlight:setHighlightColor(index, "purple"))
        assert.truthy(reader.doc_settings:flush())
        assert.equals("retained", Transaction.readTable(Transaction.metadataPath(reader.doc_settings)).unrelated_reader_setting)
        assert.is_nil(reader.doc_settings.koreaderx_transaction_blocked)
    end)
    it("rejects disk edits made after the live handle was opened", function()
        doImport()
        local index = importedIndex("first source")
        local part = reader.annotation.annotations[index].koreaderx_pdf_source.parts[1]
        local external = require("ffi/mupdf").openDocument(filename)
        local page = external:openPage(1)
        page:updateEmbeddedAnnotation(part, { contents = "external application edit" })
        page:close(); external:writeDocument(filename); external:close()
        local edited = Transaction.hash(filename)
        reader.highlight.highlight_write_into_pdf = true
        assert.is_false(reader.highlight:setHighlightColor(index, "purple"))
        assert.equals(edited, Transaction.hash(filename))
        assert.equals("external application edit", sourceEntries()[1].contents)
    end)
    it("rejects stale sources and leaves the original and metadata unchanged", function()
        doImport()
        local index = importedIndex("first source")
        local item = reader.annotation.annotations[index]
        local original = Annotation.fingerprint(item)
        local before = Transaction.hash(filename)
        item.koreaderx_pdf_source.parts[1].raw.contents = "not the source contents"
        local corrupted = Annotation.fingerprint(item)
        reader.highlight.highlight_write_into_pdf = true
        assert.is_false(reader.highlight:setHighlightColor(index, "purple"))
        assert.equals(before, Transaction.hash(filename))
        assert.equals(corrupted, Annotation.fingerprint(reader.annotation.annotations[index]))
        assert.is_not.equals(original, corrupted)
    end)
end)
