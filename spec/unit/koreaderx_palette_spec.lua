describe("KOReaderX quick palette with real ReaderUI and document engines", function()
    local ReaderUI, Registry, DocSettings, UIManager, Screen, Geom, Event, DataStorage, ffiUtil, util
    local reader, filename, serial = nil, nil, 0

    setup(function()
        require("commonrequire")
        disable_plugins()
        ReaderUI = require("apps/reader/readerui")
        Registry = require("document/documentregistry")
        DocSettings = require("docsettings")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Geom = require("ui/geometry")
        Event = require("ui/event")
        DataStorage = require("datastorage")
        ffiUtil = require("ffi/util")
        util = require("util")
    end)

    local function openReader()
        reader = ReaderUI:new{ dimen = Screen:getSize(), document = Registry:openDocument(filename), _testsuite = true }
        reader.highlight.highlight_write_into_pdf = false
        if reader.paging then
            reader.hinting.view.hinting = false
            reader:handleEvent(Event:new("SetScrollMode", false))
            reader.paging:onGotoPage(10)
        else
            reader.rolling:onGotoPage(10)
        end
        UIManager:show(reader)
    end

    local function addHighlight()
        local pos = reader.paging and Geom:new{ x = 260, y = 70 } or Geom:new{ x = 400, y = 70 }
        reader.highlight:onHold(nil, { pos = pos })
        local index = reader.highlight:saveHighlight()
        assert.is_number(index)
        local item = reader.annotation.annotations[index]
        assert.is_not.equals("", item.text)
        reader.highlight:clear()
        return index, item
    end

    local function palette(index)
        reader.highlight:showHighlightDialog(index)
        local widget = UIManager:getTopmostVisibleWidget()
        assert.equals("koreaderx_highlight_palette", widget.name)
        widget:paintTo(Screen.bb, 0, 0)
        return widget
    end

    local function tap(widget, row, column)
        local button = widget.buttontable.buttons_layout[row][column]
        assert.is_true(button.enabled)
        button:onTapSelectButton()
    end

    for _, format in ipairs({ "pdf", "epub" }) do
        describe(format, function()
            before_each(function()
                serial = serial + 1
                -- The gesture coordinates use the existing upstream sample layout.
                -- New footer dimensions have their own real-widget regression tests.
                G_reader_settings:saveSetting("footer", { container_height = 14, reclaim_height = false, highlight_navigation = false })
                G_reader_settings:saveSetting("highlight_color", "yellow")
                G_reader_settings:saveSetting("flash_ui", false)
                G_reader_settings:saveSetting("document_metadata_folder", "dir")
                DocSettings.setIsHashLocationEnabled(false)
                filename = DataStorage:getDataDir() .. "/palette-" .. serial .. "." .. format
                local source = format == "pdf" and "sample.pdf" or "juliet.epub"
                ffiUtil.copyFile("spec/front/unit/data/" .. source, filename)
                local copied = assert(io.open(filename, "rb"))
                copied:close()
                if format == "pdf" then
                    -- PDF import prompts are covered by integration specs; keep this widget test focused.
                    local settings = DocSettings:open(filename)
                    settings:saveSetting("koreaderx_pdf_import", { version = 1, tombstones = {},
                        seen_mtime = require("libs/libkoreader-lfs").attributes(filename, "modification") })
                    settings:flush()
                end
                openReader()
            end)

            after_each(function()
                if reader then reader:onClose(); reader = nil end
                UIManager:quit()
                DocSettings:open(filename):purge()
                os.remove(filename)
            end)

            it("shows four colors plus trash and More, keeps repeated edits open and persists all defaults", function()
                local index, item = addHighlight()
                local widget = palette(index)
                local rows = widget.buttontable.buttons_layout
                assert.equals(2, #rows)
                assert.equals(4, #rows[1])
                assert.equals(2, #rows[2])
                assert.same({ "Yellow", "Green", "Cyan", "Purple" }, {
                    rows[1][1].text, rows[1][2].text, rows[1][3].text, rows[1][4].text,
                })
                assert.equals("\u{F48E}", rows[2][1].text)
                assert.equals("More…", rows[2][2].text)
                for _, choice in ipairs({ { 2, "green" }, { 4, "purple" } }) do
                    tap(widget, 1, choice[1])
                    assert.equals(choice[2], item.color)
                    assert.equals(choice[2], reader.view.highlight.saved_color)
                    assert.equals(choice[2], reader.doc_settings:readSetting("highlight_color"))
                    assert.equals(choice[2], G_reader_settings:readSetting("highlight_color"))
                    assert.equals(widget, UIManager:getTopmostVisibleWidget())
                end
                UIManager:close(widget)
                reader:onClose(); reader = nil
                openReader()
                assert.equals("purple", reader.annotation.annotations[1].color)
                assert.equals("purple", reader.view.highlight.saved_color)
                assert.equals("purple", reader.doc_settings:readSetting("highlight_color"))
            end)

            it("deletes the selected highlight through the trash button", function()
                local index = addHighlight()
                local widget = palette(index)
                tap(widget, 2, 1)
                assert.equals(0, #reader.annotation.annotations)
                assert.is_not.equals(widget, UIManager:getTopmostVisibleWidget())
            end)

            it("keeps the full edit and note routes accessible through More", function()
                local index, item = addHighlight()
                tap(palette(index), 2, 2)
                local full = UIManager:getTopmostVisibleWidget()
                assert.equals("edit_highlight_dialog", full.name)
                assert.equals(6, #full.buttontable.buttons_layout[1])
                assert.equals(4, #full.buttontable.buttons_layout[2])
                tap(full, 1, 4) -- Note: actual InputDialog and actual Bookmark save.
                local editor = UIManager:getTopmostVisibleWidget()
                assert.equals("Edit note", editor.title)
                editor:setInputText("Palette note survives")
                editor.buttons[1][3].callback()
                assert.equals("Palette note survives", item.note)
                reader.highlight:showHighlightNoteOrDialog(index)
                local viewer = UIManager:getTopmostVisibleWidget()
                assert.equals("Note", viewer.title)
                assert.equals("Palette note survives", viewer.text)
                UIManager:close(viewer)
                reader:onClose(); reader = nil
                openReader()
                assert.equals("Palette note survives", reader.annotation.annotations[1].note)
            end)

            it("tracks the same annotation when the array is reordered while the palette is open", function()
                local index, item = addHighlight()
                local widget = palette(index)
                local other = util.tableDeepCopy(item)
                other.text, other.color = "unrelated annotation", "cyan"
                table.insert(reader.annotation.annotations, 1, other)
                tap(widget, 1, 4)
                assert.equals("purple", item.color)
                assert.equals("cyan", other.color)
                tap(widget, 2, 1)
                assert.equals(1, #reader.annotation.annotations)
                assert.equals(other, reader.annotation.annotations[1])
            end)

            it("does not edit, delete or open another annotation after the original is removed", function()
                for _, action in ipairs({ {1, 2}, {2, 1}, {2, 2} }) do
                    reader.annotation.annotations = {}
                    local index, item = addHighlight()
                    local widget = palette(index)
                    local other = util.tableDeepCopy(item)
                    other.text, other.color = "remaining annotation", "cyan"
                    reader.annotation.annotations[index] = other
                    tap(widget, action[1], action[2])
                    assert.equals(1, #reader.annotation.annotations)
                    assert.equals(other, reader.annotation.annotations[1])
                    assert.equals("cyan", other.color)
                    assert.is_not.equals("edit_highlight_dialog", UIManager:getTopmostVisibleWidget().name)
                    UIManager:close(widget)
                end
            end)
        end)
    end
end)
