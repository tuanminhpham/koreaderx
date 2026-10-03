describe("KOReaderX reader overlay defaults and routing", function()
    local Screen, UIManager, ReaderUI, Event, Geom
    local saved_settings, ui
    setup(function()
        require("commonrequire")
        disable_plugins()
        local Device = require("device")
        Screen = Device.screen
        require("document/canvascontext"):init(Device)
        UIManager = require("ui/uimanager")
        ReaderUI = require("apps/reader/readerui")
        Event = require("ui/event")
        Geom = require("ui/geometry")
    end)
    before_each(function()
        saved_settings = G_reader_settings.data
        G_reader_settings.data = {}
    end)
    after_each(function()
        if ui then ui:onClose(); ui = nil end
        G_reader_settings.data = saved_settings
    end)
    local function openPDF()
        local path = "spec/front/unit/data/2col.pdf"
        local ds = require("docsettings"):open(path)
        ds:purge()
        ui = ReaderUI:new{ dimen = Screen:getSize(),
            document = require("document/documentregistry"):openDocument(path) }
        UIManager:show(ui)
        UIManager:_checkTasks()
        -- The separate PDF import feature shows a modal on a new document.
        -- Close only that prompt in this host fixture before testing the panel.
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if w.modal then UIManager:close(w) end
        end
        UIManager:_repaint()
    end
    it("uses a fresh profile and document for Page/Fit full/footer/one automatic toolbar", function()
        openPDF()
        assert.are.equal("page", ui.zooming.zoom_mode)
        assert.is_false(ui.view.page_scroll)
        assert.is_true(ui.view.footer_visible)
        local toolbar = ui.gotopage.skimto
        assert.is_truthy(toolbar)
        assert.is_true(toolbar.compact_mode)
        ui.gotopage:onShowSkimtoDialog()
        assert.are.equal(toolbar, ui.gotopage.skimto)
        assert.is_nil(ui.paging.skim_backup)
        ui.zooming:onSetZoomMode("pagewidth")
        ui.gotopage:onPageUpdate()
        assert.are.equal("pagewidth", ui.zooming.zoom_mode)
        ui:saveSettings()
        assert.are.equal("pagewidth", ui.doc_settings:readSetting("zoom_mode"))
        ui:onClose()
        ui = ReaderUI:new{ dimen = Screen:getSize(),
            document = require("document/documentregistry"):openDocument("spec/front/unit/data/2col.pdf") }
        UIManager:show(ui)
        UIManager:_checkTasks()
        assert.are.equal("pagewidth", ui.zooming.zoom_mode)
    end)
    it("retains one TOC and routes toolbar/footer and outside dismissal once", function()
        openPDF()
        ui.toc:onShowToc()
        UIManager:_repaint()
        local panel, menu = ui.toc.toc_panel, ui.toc.toc_menu
        assert.is_true(menu.page_info:getSize().w <= menu.inner_dimen.w)
        ui.toc:onShowToc()
        assert.are.equal(panel, ui.toc.toc_panel)
        menu:onMenuSelect({page=1})
        assert.are.equal(panel, ui.toc.toc_panel)
        assert.are.equal(menu, ui.toc.toc_menu)
        local toolbar = ui.gotopage.skimto
        local frame = toolbar.skimto_frame.dimen
        assert.is_true(frame.y + frame.h <= Screen:getHeight() - ui.view.footer:getHeight())
        local calls = 0
        local old_handle = toolbar.handleEvent
        toolbar.handleEvent = function() calls = calls + 1 end
        UIManager:sendEvent(Event:new("Gesture", {ges="tap", pos=Geom:new{x=frame.x+1,y=frame.y+1,w=1,h=1}}))
        assert.are.equal(1,calls)
        assert.are.equal(panel, ui.toc.toc_panel)
        toolbar.handleEvent = old_handle
        local reader_calls = 0
        local old_reader_handle = ui.handleEvent
        ui.handleEvent = function() reader_calls = reader_calls + 1 end
        UIManager:sendEvent(Event:new("Gesture", {ges="tap", pos=Geom:new{x=menu.width+5,y=10,w=1,h=1}}))
        assert.is_nil(ui.toc.toc_panel)
        assert.are.equal(0, reader_calls)
        assert.are.equal(toolbar, ui.gotopage.skimto)
        ui.handleEvent = old_reader_handle
    end)
    it("honors explicit global defaults", function()
        G_reader_settings:saveSetting("kopt_page_scroll", 1)
        G_reader_settings:saveSetting("kopt_zoom_mode_genus", 4)
        G_reader_settings:saveSetting("kopt_zoom_mode_type", 1)
        G_reader_settings:saveSetting("skim_toolbar_enabled", false)
        openPDF()
        assert.are.equal("pagewidth", ui.zooming.zoom_mode)
        assert.is_true(ui.view.page_scroll)
        assert.is_nil(ui.gotopage.skimto)
    end)
end)
