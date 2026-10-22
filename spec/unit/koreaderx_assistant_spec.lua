describe("Packaged assistant integration", function()
    local UIManager, ReaderUI, PluginLoader, ui, plugin, request
    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        ReaderUI = require("apps/reader/readerui")
        PluginLoader = require("pluginloader")
        request = require("socket.http").request
        require("socket.http").request = function() error("Unexpected external request") end
        disable_plugins()
        load_plugin("assistant")
        for _, item in ipairs(PluginLoader.enabled_plugins) do
            package.path = package.path .. ";" .. item.path .. "/?.lua"
        end
        local path = "spec/front/unit/data/2col.pdf"
        ui = ReaderUI:new{ dimen = require("device").screen:getSize(),
            document = require("document/documentregistry"):openDocument(path) }
        UIManager:show(ui)
        UIManager:_checkTasks()
        -- Fresh PDF fixtures may show the separate embedded-annotation import
        -- prompt. Dismiss that known modal before testing dictionary gestures.
        for i = #UIManager._window_stack, 1, -1 do
            local widget = UIManager._window_stack[i].widget
            if widget.text == require("gettext")("The PDF is new or has changed. Import its embedded annotations without removing existing highlights?") then
                widget:onClose()
            end
        end
        plugin = PluginLoader:getPluginInstance("assistant")
    end)
    teardown(function()
        if plugin and plugin.assistant_dialog then plugin.assistant_dialog:_close() end
        if ui then ui:onClose() end
        require("socket.http").request = request
    end)
    it("loads packaged metadata/resources and uses private profile configuration", function()
        assert.is_truthy(plugin)
        assert.are.equal("readerassistant", plugin.name)
        assert.are.equal("1.09", plugin.meta.version)
        local paths = require("assistant_paths")
        assert.are.equal(require("datastorage"):getSettingsDir() .. "/assistant-configuration.lua", paths.configuration)
        assert.are.equal(paths.root .. "l10n", require("assistant_gettext").dirname)
        assert.is_truthy(plugin.assistant_dialog)
        assert.are.equal("offline", plugin.querier.provider_name)
    end)
    it("opens and cancels a local question editor without network access", function()
        assert.is_true(plugin:onAskAIQuestion())
        assert.is_truthy(plugin.assistant_dialog.input_dialog)
        plugin.assistant_dialog:_close()
        assert.is_nil(plugin.assistant_dialog.input_dialog)
    end)
    it("opens settings and persists a choice inside the active profile", function()
        plugin:showSettings()
        assert.is_truthy(plugin._settings_dialog)
        UIManager:close(plugin._settings_dialog)
        plugin.settings:saveSetting("use_stream_mode", false)
        plugin.updated = true
        plugin:onFlushSettings()
        local reread = require("luasettings"):open(plugin.settings_file)
        assert.is_false(reread:readSetting("use_stream_mode"))
        assert.are.equal(require("datastorage"):getSettingsDir() .. "/assistant.lua", plugin.settings_file)
    end)
    local function openDictionary(word)
        ui.dictionary:showDict(word, {{dict="Local fixture", word=word,
            definition="Local dictionary fixture; no service is contacted."}})
        UIManager:_repaint()
        assert.are.equal(ui.dictionary.dict_window, UIManager._window_stack[#UIManager._window_stack].widget)
        return ui.dictionary.dict_window
    end
    local function closeDictionary(popup)
        popup:onClose(true)
        ui.dictionary.dict_window = nil
    end
    it("registers one dictionary row and preserves customized button layouts", function()
        local util = require("util")
        local saved = G_reader_settings:readSetting("dict_button_config")
        local config = {layout={{"highlight", "search"}, {"close"}}}
        G_reader_settings:saveSetting("dict_button_config", util.tableDeepCopy(config))
        plugin:registerDictButtons()
        plugin:registerDictButtons()
        local popup = openDictionary("extracurriculars")
        local counts = {}
        local assistant_rows = 0
        for _, row in ipairs(popup:buildButtonLayout()) do
            local ai_row = false
            for _, button in ipairs(row) do
                if button.id and button.id:match("^assistant_") then
                    counts[button.id] = (counts[button.id] or 0) + 1
                    ai_row = true
                end
            end
            if ai_row then assistant_rows = assistant_rows + 1 end
        end
        assert.are.equal(1, counts.assistant_dictionary)
        assert.are.equal(1, counts.assistant_wikipedia)
        assert.are.equal(1, assistant_rows)
        assert.is_truthy(popup.button_table:getButtonById("assistant_dictionary"))
        assert.is_truthy(popup.button_table:getButtonById("assistant_wikipedia"))
        assert.are.same(config, G_reader_settings:readSetting("dict_button_config"))
        closeDictionary(popup)
        G_reader_settings:saveSetting("dict_button_config", saved)
    end)
    it("applies each dictionary checkbox when the next popup is built", function()
        plugin.settings:saveSetting("dict_popup_show_dictionary", false)
        local popup = openDictionary("first")
        assert.is_nil(popup.button_table:getButtonById("assistant_dictionary"))
        assert.is_truthy(popup.button_table:getButtonById("assistant_wikipedia"))
        closeDictionary(popup)
        plugin.settings:saveSetting("dict_popup_show_wikipedia", false)
        popup = openDictionary("second")
        assert.is_nil(popup.button_table:getButtonById("assistant_dictionary"))
        assert.is_nil(popup.button_table:getButtonById("assistant_wikipedia"))
        closeDictionary(popup)
        plugin.settings:saveSetting("dict_popup_show_dictionary", true)
        plugin.settings:saveSetting("dict_popup_show_wikipedia", true)
    end)
    it("routes dictionary button taps once with the popup word and no offline network gate", function()
        local NetworkMgr = require("ui/network/manager")
        local online, query, show_error = NetworkMgr.runWhenOnline, plugin.querier.query, plugin.querier.showError
        local saved_flash = G_reader_settings:readSetting("flash_ui")
        local queries = {}
        local popup
        NetworkMgr.runWhenOnline = function() error("Unexpected network gate") end
        plugin.querier.query = function(_, messages)
            queries[#queries+1] = messages[#messages].content
            return nil, "Local fixture stops before any service request."
        end
        plugin.querier.showError = function() end
        G_reader_settings:saveSetting("flash_ui", false)
        local ok, err = pcall(function()
            popup = openDictionary("extracurriculars")
            for _, id in ipairs({"assistant_dictionary", "assistant_wikipedia"}) do
                local button = popup.button_table:getButtonById(id)
                local frame = button.dimen
                UIManager:sendEvent(require("ui/event"):new("Gesture", {
                    ges="tap", pos=require("ui/geometry"):new{
                        x=frame.x+frame.w/2, y=frame.y+frame.h/2, w=1, h=1},
                }))
            end
            assert.are.equal(2, #queries)
            assert.is_truthy(queries[1]:find("extracurriculars", 1, true))
            assert.is_truthy(queries[2]:find("extracurriculars", 1, true))
        end)
        if popup then closeDictionary(popup) end
        NetworkMgr.runWhenOnline, plugin.querier.query, plugin.querier.showError = online, query, show_error
        G_reader_settings:saveSetting("flash_ui", saved_flash)
        assert.is_true(ok, err)
    end)
    it("leaves footer, compact toolbar and persistent TOC functional", function()
        assert.is_true(ui.view.footer_visible)
        assert.is_truthy(ui.gotopage.skimto)
        ui.toc:onShowToc()
        local panel = ui.toc.toc_panel
        ui.toc.toc_menu:onMenuSelect({page=1})
        assert.are.equal(panel, ui.toc.toc_panel)
        assert.is_truthy(ui.gotopage.skimto)
    end)
    it("rejects an unconfigured query locally without inventing an answer", function()
        local result, err = require("api_handlers.offline"):query({})
        assert.is_nil(result)
        assert.is_truthy(err:find("No request was sent", 1, true))
    end)
end)
