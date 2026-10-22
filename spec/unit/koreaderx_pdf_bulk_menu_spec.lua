describe("KOReaderX PDF bulk annotation menu availability", function()
    local ReaderUI, Registry, UIManager, Screen, Transaction, util, ffiUtil
    local reader, directory

    setup(function()
        require("commonrequire")
        disable_plugins()
        ReaderUI = require("apps/reader/readerui")
        Registry = require("document/documentregistry")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Transaction = require("document/pdfannotationtransaction")
        util = require("util")
        ffiUtil = require("ffi/util")
    end)

    before_each(function()
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        directory = os.tmpname()
        os.remove(directory)
        util.makePath(directory)
        local filename = directory .. "/bulk-menu.pdf"
        Transaction.copy("spec/front/unit/data/sample.pdf", filename)
        reader = ReaderUI:new{ dimen = Screen:getSize(), document = Registry:openDocument(filename) }
    end)

    after_each(function()
        reader.highlight.highlight_write_into_pdf = false
        reader:onClose()
        reader = nil
        UIManager:quit()
        assert(ffiUtil.purgeDir(directory))
    end)

    local function highlight(note)
        return { page = 1, text = "Fixture text", drawer = "lighten", note = note }
    end

    local function findBulkMenuItem(label)
        local menu_items = {}
        reader.highlight:addToMainMenu(menu_items)
        for _, item in ipairs(menu_items.highlight_options.sub_item_table) do
            for _, sub_item in ipairs(item.sub_item_table or {}) do
                if sub_item.text == label then return sub_item end
            end
        end
        error("Missing bulk PDF command: " .. label)
    end

    local scenarios = {
        { name = "four highlights with notes", write = true,
            annotations = { highlight("first"), highlight("second"), highlight("third"), highlight("fourth") },
            expected = true },
        { name = "a highlight without a note", write = true,
            annotations = { highlight() }, expected = true },
        { name = "mixed highlights and notes", write = true,
            annotations = { highlight(), highlight("note") }, expected = true },
        { name = "no annotations", write = true,
            annotations = {}, expected = false },
        { name = "page bookmarks only", write = true,
            annotations = {{ page = 1, text = "Page bookmark" }}, expected = false },
        { name = "write-PDF explicitly off", write = false,
            annotations = { highlight() }, expected = false },
        { name = "write-PDF unset", write = nil,
            annotations = { highlight("note") }, expected = false },
    }
    for _, label in ipairs({ "Write all highlights into PDF file", "Delete all highlights from PDF file" }) do
        for _, scenario in ipairs(scenarios) do
            it(label .. ": " .. scenario.name, function()
                reader.annotation.annotations = util.tableDeepCopy(scenario.annotations)
                reader.highlight.highlight_write_into_pdf = scenario.write
                -- Exercise the predicate registered by the real reader menu,
                -- including the real two-result annotation counting method.
                assert.equals(scenario.expected, findBulkMenuItem(label).enabled_func())
            end)
        end
    end
end)
