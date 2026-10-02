local BlitBuffer = require("ffi/blitbuffer")
local CacheItem = require("cacheitem")
local CanvasContext = require("document/canvascontext")
local DocCache = require("document/doccache")
local DocSettings = require("docsettings")
local Document = require("document/document")
local DrawContext = require("ffi/drawcontext")
local logger = require("logger")
local util = require("util")
local ffi = require("ffi")
local C = ffi.C
local pdf = nil

local PdfDocument = Document:extend{
    _document = false,
    is_pdf = true,
    dc_null = DrawContext.new(),
    koptinterface = nil,
    provider = "mupdf",
    provider_name = "MuPDF",
}

function PdfDocument:init()
    local Transaction = require("document/pdfannotationtransaction")
    Transaction.recover(self.file)
    self.koreaderx_open_hash = self:supportsEmbeddedAnnotations() and Transaction.hash(self.file) or nil
    if not pdf then pdf = require("ffi/mupdf") end
    self.koptinterface = require("document/koptinterface")
    self.koptinterface:setDefaultConfigurable(self.configurable)
    local ok
    ok, self._document = pcall(pdf.openDocument, self.file)
    if not ok then
        error(self._document)  -- will contain error message
    end
    self:updateColorRendering()
    self.is_reflowable = self._document:isDocumentReflowable()
    self.reflowable_font_size = self:convertKoptToReflowableFontSize()
    -- no-op on PDF
    self:layoutDocument()
    self.is_open = true
    self.info.has_pages = true
    self.info.configurable = true
    self.render_mode = 0
    if self._document:needsPassword() then
        self.is_locked = true
    else
        self:_readMetadata()
    end
end

function PdfDocument:updateColorRendering()
    Document.updateColorRendering(self) -- will set self.render_color
    if self._document then
        self._document:setColorRendering(self.render_color)
    end
end

function PdfDocument:layoutDocument(font_size)
    if font_size then
        self.reflowable_font_size = font_size
    end
    self._document:layoutDocument(
        CanvasContext:getWidth(),
        CanvasContext:getHeight(),
        CanvasContext:scaleBySize(self.reflowable_font_size))
end

local default_font_size = 22
-- the koptreader config goes from 0.1 to 3.0, but we want a regular font size
function PdfDocument:convertKoptToReflowableFontSize(font_size)
    if font_size then
        return font_size * default_font_size
    end

    local size
    if DocSettings:hasSidecarFile(self.file) then
        local doc_settings = DocSettings:open(self.file)
        size = doc_settings:readSetting("kopt_font_size")
    end
    if size then
        return size * default_font_size
    elseif G_reader_settings:readSetting("kopt_font_size") then
        return G_reader_settings:readSetting("kopt_font_size") * default_font_size
    elseif G_defaults:readSetting("DKOPTREADER_CONFIG_FONT_SIZE") then
        return G_defaults:readSetting("DKOPTREADER_CONFIG_FONT_SIZE") * default_font_size
    else
        return default_font_size
    end
end

function PdfDocument:unlock(password)
    if not self._document:authenticatePassword(password) then
        return false
    end
    self.koreaderx_password = password -- transient; never stored in metadata
    self.is_locked = false
    self:_readMetadata()
    return true
end

function PdfDocument:comparePositions(pos1, pos2)
    return self.koptinterface:comparePositions(self, pos1, pos2)
end

function PdfDocument:getPageTextBoxes(pageno)
    local hash = "textbox|"..self.file.."|"..pageno
    local cached = DocCache:check(hash)
    if not cached then
        local page = self._document:openPage(pageno)
        local text = page:getPageText()
        page:close()
        DocCache:insert(hash, CacheItem:new{text=text, size=text.size})
        return text
    else
        return cached.text
    end
end

function PdfDocument:getPanelFromPage(pageno, pos)
    return self.koptinterface:getPanelFromPage(self, pageno, pos)
end

function PdfDocument:getWordFromPosition(spos)
    return self.koptinterface:getWordFromPosition(self, spos)
end

function PdfDocument:getTextFromPositions(spos0, spos1)
    return self.koptinterface:getTextFromPositions(self, spos0, spos1)
end

function PdfDocument:getTextBoxes(pageno)
    return self.koptinterface:getTextBoxes(self, pageno)
end

function PdfDocument:getPageBoxesFromPositions(pageno, ppos0, ppos1)
    return self.koptinterface:getPageBoxesFromPositions(self, pageno, ppos0, ppos1)
end

function PdfDocument:nativeToPageRectTransform(pageno, rect)
    return self.koptinterface:nativeToPageRectTransform(self, pageno, rect)
end

function PdfDocument:getSelectedWordContext(word, nb_words, pos)
    return self.koptinterface:getSelectedWordContext(word, nb_words, pos)
end

function PdfDocument:getOCRWord(pageno, wbox)
    return self.koptinterface:getOCRWord(self, pageno, wbox)
end

function PdfDocument:getOCRText(pageno, tboxes)
    return self.koptinterface:getOCRText(self, pageno, tboxes)
end

function PdfDocument:getPageBlock(pageno, x, y)
    return self.koptinterface:getPageBlock(self, pageno, x, y)
end

function PdfDocument:getUsedBBox(pageno)
    local hash = "pgubbox|"..self.file.."|"..self.reflowable_font_size.."|"..pageno
    local cached = DocCache:check(hash)
    if cached then
        return cached.ubbox
    end
    local page = self._document:openPage(pageno)
    local used = {}
    used.x0, used.y0, used.x1, used.y1 = page:getUsedBBox()
    local pwidth, pheight = page:getSize(self.dc_null)
    -- clamp to page BBox
    if used.x0 < 0 then used.x0 = 0 end
    if used.x1 > pwidth then used.x1 = pwidth end
    if used.y0 < 0 then used.y0 = 0 end
    if used.y1 > pheight then used.y1 = pheight end
    DocCache:insert(hash, CacheItem:new{
        ubbox = used,
        size = 256, -- might be closer to 160
    })
    page:close()
    return used
end

function PdfDocument:getPageLinks(pageno)
    local hash = "pglinks|"..self.file.."|"..self.reflowable_font_size.."|"..pageno
    local cached = DocCache:check(hash)
    if cached then
        return cached.links
    end
    local page = self._document:openPage(pageno)
    local links = page:getPageLinks()
    DocCache:insert(hash, CacheItem:new{
        links = links,
        size = 64 + (8 * 32 * #links),
    })
    page:close()
    return links
end

-- returns nil if file is not a pdf, true if document is a writable pdf, false else
function PdfDocument:_checkIfWritable()
    if self.koreaderx_transaction_blocked then return false end
    local suffix = util.getFileNameSuffix(self.file)
    if string.lower(suffix) ~= "pdf" then return nil end
    if self.is_writable == nil then
        local handle = io.open(self.file, 'r+b')
        self.is_writable = handle ~= nil
        if handle then handle:close() end
    end
    return self.is_writable
end

local function _quadpointsFromPboxes(pboxes)
    -- will also need mupdf_h.lua to be evaluated once
    -- but this is guaranteed at this point
    local n = #pboxes
    local quadpoints = ffi.new("fz_quad[?]", n)
    for i=1, n do
        -- The order must be left bottom, right bottom, left top, right top.
        -- https://bugs.ghostscript.com/show_bug.cgi?id=695130
        quadpoints[i-1].ll.x = pboxes[i].x
        quadpoints[i-1].ll.y = pboxes[i].y + pboxes[i].h - 1
        quadpoints[i-1].lr.x = pboxes[i].x + pboxes[i].w - 1
        quadpoints[i-1].lr.y = pboxes[i].y + pboxes[i].h - 1
        quadpoints[i-1].ul.x = pboxes[i].x
        quadpoints[i-1].ul.y = pboxes[i].y
        quadpoints[i-1].ur.x = pboxes[i].x + pboxes[i].w - 1
        quadpoints[i-1].ur.y = pboxes[i].y
    end
    return quadpoints, n
end

local function _quadpointsToPboxes(quadpoints, n)
    -- reverse of previous function
    local pboxes = {}
    for i=1, n do
        table.insert(pboxes, {
            x = quadpoints[i-1].ul.x,
            y = quadpoints[i-1].ul.y,
            w = quadpoints[i-1].lr.x - quadpoints[i-1].ul.x + 1,
            h = quadpoints[i-1].lr.y - quadpoints[i-1].ul.y + 1,
        })
    end
    return pboxes
end

function PdfDocument:saveHighlight(pageno, item)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot_type = C.PDF_ANNOT_HIGHLIGHT
    local annot_color = item.color and BlitBuffer.colorFromName(item.color)
    if item.drawer == "lighten" then
        annot_type = C.PDF_ANNOT_HIGHLIGHT
    elseif item.drawer == "underscore" then
        annot_type = C.PDF_ANNOT_UNDERLINE
    elseif item.drawer == "strikeout" then
        annot_type = C.PDF_ANNOT_STRIKE_OUT
    end
    -- NOTE: For highlights, display style may differ compared to ReaderView:drawHighlightRect...
    --       (e.g., we do a MUL blend, MuPDF currently appears to do an OVER blend).
    page:addMarkupAnnotation(quadpoints, n, annot_type, annot_color) -- may update/adjust quadpoints
    -- Update pboxes with the possibly adjusted coordinates (this will have it updated
    -- in self.view.highlight.saved[page])
    item.pboxes = _quadpointsToPboxes(quadpoints, n)
    page:close()
    self:resetTileCacheValidity()
end

function PdfDocument:deleteHighlight(pageno, item)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot = page:getMarkupAnnotation(quadpoints, n)
    if annot ~= nil then
        page:deleteAnnotation(annot)
        self:resetTileCacheValidity()
    end
    page:close()
end

function PdfDocument:updateHighlightContents(pageno, item, contents)
    local can_write = self:_checkIfWritable()
    if can_write ~= true then return can_write end

    self.is_edited = true
    local quadpoints, n = _quadpointsFromPboxes(item.pboxes)
    local page = self._document:openPage(pageno)
    local annot = page:getMarkupAnnotation(quadpoints, n)
    if annot ~= nil then
        page:updateMarkupAnnotation(annot, contents)
        self:resetTileCacheValidity()
    end
    page:close()
end

function PdfDocument:supportsEmbeddedAnnotations()
    return util.getFileNameSuffix(self.file):lower() == "pdf"
end

function PdfDocument:checkPdfFileUnchanged()
    assert(not self.koreaderx_open_hash or require("document/pdfannotationtransaction").hash(self.file) == self.koreaderx_open_hash,
        "PDF changed outside KOReader. Close and reopen the document before importing or editing annotations.")
end

function PdfDocument:getEmbeddedAnnotations()
    if not self:supportsEmbeddedAnnotations() then return nil, {} end
    self:checkPdfFileUnchanged()
    local annotations, rejected = {}, {}
    for pageno = 1, self.info.number_of_pages do
        local page = self._document:openPage(pageno)
        local ok, page_annots, invalid = pcall(page.getEmbeddedAnnotations, page)
        page:close()
        assert(ok, page_annots)
        if page_annots then annotations[pageno] = page_annots end
        for _, reason in ipairs(invalid or {}) do
            rejected[#rejected + 1] = { page = pageno, reason = reason }
        end
    end
    self.koreaderx_rejected_annotations = rejected
    return next(annotations) and annotations, rejected
end
-- All imported-annotation rendering state is derived from sidecar data; it is
-- never serialized as a pointer or by changing flags on PDF objects.
function PdfDocument:setImportedAnnotations(annotations)
    local Annotation = require("document/pdfannotations")
    self._document.annotation_render_filter = {}
    self.koreaderx_render_revision = {}
    local page_data = {}
    for _, item in ipairs(annotations) do
        if item.koreaderx_pdf_source then
            for _, part in ipairs(item.koreaderx_pdf_source.parts) do
                local page = part.page
                page_data[page] = page_data[page] or {}
                table.insert(page_data[page], { source = part, override = item.koreaderx_pdf_visual_override,
                    color = item.color, drawer = item.drawer, pboxes = item.pboxes, ext = item.ext })
                if item.koreaderx_pdf_visual_override then
                    local filters = self._document.annotation_render_filter
                    filters[page] = filters[page] or {}
                    table.insert(filters[page], part)
                end
            end
        end
    end
    for page, data in pairs(page_data) do
        self.koreaderx_render_revision[page] = Annotation.fingerprint(data)
    end
    self:resetTileCacheValidity()
end

-- Revalidate before suppressing an overlay. Stale/ambiguous sources retain
-- their native appearance and block further edits instead of guessing.
function PdfDocument:importedAnnotationState(item, pageno)
    local source = item.koreaderx_pdf_source
    if not source then return "local" end
    local part
    for _, candidate in ipairs(source.parts) do
        if candidate.page == pageno then part = candidate; break end
    end
    if not part then return item.koreaderx_pdf_visual_override and "override" or "missing" end
    local page = self._document:openPage(pageno)
    local ok, pointer = pcall(page.resolveEmbeddedAnnotation, page, part)
    page:close()
    if not ok or not pointer then return "stale" end
    return item.koreaderx_pdf_visual_override and "override" or "native"
end

function PdfDocument:validateImportedAnnotation(item)
    self:checkPdfFileUnchanged()
    for _, part in ipairs(item.koreaderx_pdf_source.parts) do
        local page = self._document:openPage(part.page)
        local ok, pointer, reason = pcall(page.resolveEmbeddedAnnotation, page, part)
        page:close()
        assert(ok and pointer, reason or "PDF annotation changed externally; import/reconcile before editing")
    end
end

function PdfDocument:commitImportedAnnotation(settings, metadata, item, action)
    local Transaction = require("document/pdfannotationtransaction")
    local Annotation = require("document/pdfannotations")
    assert(self:_checkIfWritable(), "PDF is read-only")
    assert(not self.koreaderx_transaction_blocked, "PDF transaction recovery is required")
    Transaction.assertMetadataUnchanged(settings)
    Transaction.recover(self.file)
    self:validateImportedAnnotation(item)
    local id = Transaction.id()
    local before = Transaction.hash(self.file)
    local snapshot = self.file .. ".koreaderx-" .. id .. ".snapshot"
    local staged = self.file .. ".koreaderx-" .. id .. ".new"
    self._document:saveSnapshot(snapshot)
    local candidate = pdf.openDocument(snapshot)
    local candidate_open = true
    local function withPage(number, callback)
        local page = candidate:openPage(number)
        local ok, result = pcall(callback, page)
        page:close()
        assert(ok, result)
        return result
    end
    local ok, result = pcall(function()
        if candidate:needsPassword() then
            assert(self.koreaderx_password and candidate:authenticatePassword(self.koreaderx_password),
                "Cannot unlock candidate PDF")
        end
        local change_geometry = action == "geometry" or (action == "all"
            and item.koreaderx_pdf_visual_override and item.koreaderx_pdf_visual_override.geometry)
        local parts = item.koreaderx_pdf_source.parts
        local template_part = parts[1]
        local old_parts, new_parts = {}, {}
        for _, part in ipairs(parts) do old_parts[part.page] = part end
        if action == "delete" or action == "detach" then
            for _, part in ipairs(parts) do
                withPage(part.page, function(page) return page:deleteEmbeddedAnnotation(part) end)
            end
            if action == "detach" then
                item.koreaderx_pdf_source, item.koreaderx_pdf_visual_override = nil, nil
            end
        else
            local pages = {}
            if change_geometry then
                for number = item.pos0.page, item.pos1.page do pages[#pages + 1] = number end
            else
                for _, part in ipairs(parts) do pages[#pages + 1] = part.page end
            end
            for _, number in ipairs(pages) do
                local part = old_parts[number]
                local changes = {}
                if change_geometry then
                    changes.quads = Annotation.quads(item.ext and item.ext[number].pboxes or item.pboxes)
                end
                if action == "color" or action == "appearance" or (action == "all" and item.koreaderx_pdf_visual_override and item.koreaderx_pdf_visual_override.color) then
                    local hex = assert(BlitBuffer.HIGHLIGHT_COLORS[item.color])
                    local r, g, b = hex:match("#(..)(..)(..)")
                    changes.color_n = 3
                    changes.color_components = { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
                end
                if action == "note" or action == "all" then changes.contents = item.note or "" end
                if action == "style" or action == "appearance" or (action == "all" and item.koreaderx_pdf_visual_override and item.koreaderx_pdf_visual_override.style) then
                    changes.type = Annotation.types[item.drawer]
                end
                local updated = withPage(number, function(page)
                    if part then return page:updateEmbeddedAnnotation(part, changes) end
                    local raw = util.tableDeepCopy(parts[1].raw)
                    raw.quads = Annotation.quads(item.ext and item.ext[number].pboxes or item.pboxes)
                    for field, value in pairs(changes) do raw[field] = type(value) == "table" and util.tableDeepCopy(value) or value end
                    return page:createEmbeddedAnnotation(raw, template_part)
                end)
                updated.page = number
                if number == template_part.page then template_part = updated end
                new_parts[#new_parts + 1] = updated
                old_parts[number] = nil
            end
            for number, part in pairs(old_parts) do
                withPage(number, function(page) return page:deleteEmbeddedAnnotation(part) end)
            end
            item.koreaderx_pdf_source.parts = new_parts
            -- A prior local-only change is not implicitly written by toggling
            -- write-to-PDF. Keep the visual override until all fields match.
            local visual = item.koreaderx_pdf_visual_override
            if action == "all" then visual = nil; item.koreaderx_pdf_visual_override = nil end
            if type(visual) == "table" then
                visual[action] = nil
                if action == "appearance" then visual.color, visual.style = nil, nil end
                item.koreaderx_pdf_visual_override = next(visual) and visual or nil
            end
            if (action == "style" or action == "appearance" or action == "all") and not Annotation.types[item.drawer] then
                item.koreaderx_pdf_visual_override = item.koreaderx_pdf_visual_override or {}
                item.koreaderx_pdf_visual_override.style = true
            end
        end
        candidate:writeDocument(staged)
        candidate:close()
        candidate_open = false
        -- Save may renumber xrefs: reopen and validate every updated source,
        -- keeping the returned identity rather than the old locator.
        candidate = pdf.openDocument(staged)
        candidate_open = true
        if candidate:needsPassword() then assert(candidate:authenticatePassword(self.koreaderx_password)) end
        if action ~= "delete" and action ~= "detach" then
            for _, part in ipairs(item.koreaderx_pdf_source.parts) do
                withPage(part.page, function(page)
                    local pointer, entry = page:resolveEmbeddedAnnotation(part)
                    assert(pointer, entry)
                    part.num, part.gen, part.raw = entry.source.num, entry.source.gen, entry.raw
                end)
            end
        end
        candidate:close()
        candidate_open = false
        local destination, new_hash_directory
        if G_reader_settings:readSetting("document_metadata_folder", "doc") == "hash" then
            local old_hash_directory = settings:getSidecarDir(self.file, "hash")
            assert(not settings.source_candidate or settings.source_candidate:sub(1, #old_hash_directory + 1) == old_hash_directory .. "/",
                "Save and reopen the book after changing metadata storage to hash before writing PDF annotations")
            new_hash_directory = settings:getSidecarDir(staged, "hash")
            util.makePath(new_hash_directory)
            destination = new_hash_directory .. "/" .. settings.sidecar_filename
            for _, custom_file in ipairs({ settings:getCustomCoverFile(), settings:getCustomMetadataFile() }) do
                if custom_file then
                    local target = new_hash_directory .. "/" .. require("ffi/util").basename(custom_file)
                    if target ~= custom_file then
                        local target_hash = Transaction.hash(target)
                        assert(target_hash == "absent" or target_hash == Transaction.hash(custom_file), "Conflicting custom metadata in new hash location")
                        if target_hash == "absent" then Transaction.copy(custom_file, target) end
                    end
                end
            end
        end
        if metadata.koreaderx_pdf_import then
            metadata.koreaderx_pdf_import.seen_mtime = require("libs/libkoreader-lfs").attributes(staged, "modification")
        end
        local staged_metadata = Transaction.stageMetadata(settings, metadata, id, destination)
        Transaction.commitPair(self.file, staged, staged_metadata, id, before)
        settings.source_candidate = staged_metadata.path
        settings.hash_sidecar_dir = new_hash_directory or settings.hash_sidecar_dir
        DocSettings.invalidateDocumentHash(self.file)
        settings:getCustomCoverFile(true)
        settings:getCustomMetadataFile(true)
        settings.data = metadata
        Transaction.observeMetadata(settings, staged_metadata.path, staged_metadata.after)
    end)
    if candidate_open then pcall(candidate.close, candidate) end
    -- Once the disk PDF changed, the old handle must never autosave over it.
    -- A durable journal either completes the pair or blocks all further writes.
    if Transaction.hash(self.file) ~= before then
        local recovered, recover_error = pcall(Transaction.recover, self.file)
        self.is_edited = false
        self._document:close()
        self._document = pdf.openDocument(self.file)
        if self._document:needsPassword() then assert(self._document:authenticatePassword(self.koreaderx_password)) end
        self:updateColorRendering()
        self.mod_time = require("libs/libkoreader-lfs").attributes(self.file, "modification")
        self.koreaderx_open_hash = Transaction.hash(self.file)
        DocSettings.invalidateDocumentHash(self.file)
        if G_reader_settings:readSetting("document_metadata_folder", "doc") == "hash" then
            settings.hash_sidecar_dir = settings:getSidecarDir(self.file, "hash")
            settings.source_candidate = settings.hash_sidecar_dir .. "/" .. settings.sidecar_filename
        end
        self:resetTileCacheValidity()
        if not recovered then
            self.koreaderx_transaction_blocked = true
            settings.koreaderx_transaction_blocked = true
            error(recover_error)
        end
        if not ok then
            -- A failed rename may have been completed by recovery. Only treat
            -- it as success if the durable metadata exactly matches candidate.
            local disk = Transaction.readTable(Transaction.metadataPath(settings))
            if Annotation.fingerprint(disk) == Annotation.fingerprint(metadata) then
                settings.data = metadata
                Transaction.observeMetadata(settings, Transaction.metadataPath(settings))
                ok = true
            end
        end
    end
    assert(ok, result)
end

function PdfDocument:writeDocument()
    assert(not self.koreaderx_transaction_blocked, "PDF transaction recovery is required before saving")
    logger.info("writing document to", self.file)
    self:checkPdfFileUnchanged()
    self._document:writeDocument(self.file)
    self.koreaderx_open_hash = require("document/pdfannotationtransaction").hash(self.file)
end

function PdfDocument:close()
    -- NOTE: We can't just rely on Document:close's return code for that, as we need self._document
    --       in :writeDocument, and it would have been destroyed.
    local DocumentRegistry = require("document/documentregistry")
    if DocumentRegistry:getReferenceCount(self.file) == 1 then
        -- We're the final reference to this Document instance.
        if self.is_edited and not self.koreaderx_transaction_blocked then
            self:writeDocument()
        end
    end

    Document.close(self)
end

function PdfDocument:getLinkFromPosition(pageno, pos)
    return self.koptinterface:getLinkFromPosition(self, pageno, pos)
end

function PdfDocument:clipPagePNGFile(pos0, pos1, pboxes, drawer, filename)
    return self.koptinterface:clipPagePNGFile(self, pos0, pos1, pboxes, drawer, filename)
end

function PdfDocument:clipPagePNGString(pos0, pos1, pboxes, drawer)
    return self.koptinterface:clipPagePNGString(self, pos0, pos1, pboxes, drawer)
end

function PdfDocument:getPageBBox(pageno)
    return self.koptinterface:getPageBBox(self, pageno)
end

function PdfDocument:getPageDimensions(pageno, zoom, rotation)
    return self.koptinterface:getPageDimensions(self, pageno, zoom, rotation)
end

function PdfDocument:getCoverPageImage()
    return self.koptinterface:getCoverPageImage(self)
end

function PdfDocument:findText(pattern, origin, reverse, case_insensitive, page)
    return self.koptinterface:findText(self, pattern, origin, reverse, case_insensitive, page)
end

function PdfDocument:findAllText(pattern, case_insensitive, nb_context_words, max_hits)
    return self.koptinterface:findAllText(self, pattern, case_insensitive, nb_context_words, max_hits)
end

function PdfDocument:renderPage(pageno, rect, zoom, rotation, gamma, saturation, hinting)
    return self.koptinterface:renderPage(self, pageno, rect, zoom, rotation, gamma, saturation, hinting)
end

function PdfDocument:hintPage(pageno, zoom, rotation, gamma, saturation)
    return self.koptinterface:hintPage(self, pageno, zoom, rotation, gamma, saturation)
end

function PdfDocument:drawPage(target, x, y, rect, pageno, zoom, rotation, gamma, saturation)
    return self.koptinterface:drawPage(self, target, x, y, rect, pageno, zoom, rotation, gamma, saturation)
end

function PdfDocument:register(registry)
    --- Document types ---
    registry:addProvider("cbr", "application/vnd.comicbook-rar", self, 100)
    registry:addProvider("cbr", "application/vnd.rar", self, 100)
    registry:addProvider("cbt", "application/vnd.comicbook+tar", self, 100)
    registry:addProvider("cbz", "application/vnd.comicbook+zip", self, 100)
    registry:addProvider("cbz", "application/x-cbz", self, 100) -- Alternative mimetype for OPDS.
    registry:addProvider("cfb", "application/octet-stream", self, 80) -- Compound File Binary, a Microsoft general-purpose file with a file-system-like structure.
    registry:addProvider("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", self, 80)
    registry:addProvider("epub", "application/epub+zip", self, 50)
    registry:addProvider("epub3", "application/epub+zip", self, 50)
    registry:addProvider("fb2", "application/fb2", self, 80)
    registry:addProvider("htm", "text/html", self, 90)
    registry:addProvider("html", "text/html", self, 90)
    registry:addProvider("mobi", "application/x-mobipocket-ebook", self, 80)
    registry:addProvider("pdf", "application/pdf", self, 100)
    registry:addProvider("pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation", self, 80)
    registry:addProvider("tar", "application/x-tar", self, 10)
    registry:addProvider("txt", "text/plain", self, 80)
    registry:addProvider("xhtml", "application/xhtml+xml", self, 90)
    registry:addProvider("xml", "application/xml", self, 10)
    registry:addProvider("xps", "application/oxps", self, 100)
    registry:addProvider("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", self, 80)
    registry:addProvider("zip", "application/zip", self, 20)

    --- Picture types ---
    registry:addProvider("gif", "image/gif", self, 90)
    -- MS HD Photo == JPEG XR
    registry:addProvider("hdp", "image/vnd.ms-photo", self, 90)
    registry:addProvider("j2k", "image/jp2", self, 90)
    registry:addProvider("jp2", "image/jp2", self, 90)
    registry:addProvider("jpeg", "image/jpeg", self, 90)
    registry:addProvider("jpg", "image/jpeg", self, 90)
    -- JPEG XR
    registry:addProvider("jxr", "image/jxr", self, 90)
    registry:addProvider("pam", "image/x-portable-arbitrarymap", self, 90)
    registry:addProvider("pbm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("pgm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("png", "image/png", self, 90)
    registry:addProvider("pnm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("ppm", "image/x‑portable‑bitmap", self, 90)
    registry:addProvider("svg", "image/svg+xml", self, 80)
    registry:addProvider("tif", "image/tiff", self, 90)
    registry:addProvider("tiff", "image/tiff", self, 90)
    -- Windows Media Photo == JPEG XR
    registry:addProvider("wdp", "image/vnd.ms-photo", self, 90)
end

return PdfDocument
