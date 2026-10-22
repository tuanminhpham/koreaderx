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
