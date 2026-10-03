describe("KOReaderX skim layout with real widgets", function()
    local SkimToWidget, Device, Screen, Blitbuffer
    local old_width, old_height, old_dpad, old_position
    setup(function()
        require("commonrequire")
        Device = require("device")
        Screen = Device.screen
        require("document/canvascontext"):init(Device)
        Blitbuffer = require("ffi/blitbuffer")
        SkimToWidget = require("ui/widget/skimtowidget")
        old_width, old_height, old_dpad = Screen.getWidth, Screen.getHeight, Device.hasDPad
        old_position = G_reader_settings:readSetting("skim_dialog_position")
    end)
    teardown(function()
        Screen.getWidth, Screen.getHeight, Device.hasDPad = old_width, old_height, old_dpad
        G_reader_settings:saveSetting("skim_dialog_position", old_position)
    end)
    for _, size in ipairs({ {600, 800}, {800, 600}, {1200, 1600}, {1600, 1200} }) do
        for _, position in ipairs({ "top", "bottom", "full" }) do
            it("fits " .. position .. " at " .. size[1] .. "x" .. size[2] .. " and exposes its visible controls", function()
                Screen.getWidth = function() return size[1] end
                Screen.getHeight = function() return size[2] end
                Device.hasDPad = function() return true end
                G_reader_settings:saveSetting("skim_dialog_position", position ~= "full" and position or "center")
                local page, history, entered, exited = 10, 0, 0, 0
                local ui = {
                    paging = {
                        enterSkimMode = function() entered = entered + 1 end,
                        exitSkimMode = function() exited = exited + 1 end,
                    },
                    getCurrentPage = function() return page end,
                    document = { getPageCount = function() return 100 end },
                    toc = { getTocTicksFlattened = function() return {} end },
                    view = { footer_visible = true, footer = { getHeight = function() return 57 end },
                        shouldInvertBiDiLayoutMirroring = function() return false end },
                    link = { addCurrentLocationToStack = function() history = history + 1 end },
                    handleEvent = function(_, ev)
                        if ev.handler == "onGotoPage" then page = ev.args[1] end
                    end,
                }
                local widget = SkimToWidget:new{ ui = ui, callback_switch_to_goto = function() end }
                local bb = Blitbuffer.new(size[1], size[2], Blitbuffer.TYPE_BB8)
                bb:fill(Blitbuffer.COLOR_WHITE)
                widget:paintTo(bb, 0, 0)
                local frame = widget.skimto_frame.dimen
                assert.is_true(frame.x >= 0 and frame.y >= 0)
                assert.is_true(frame.x + frame.w <= size[1])
                assert.is_true(frame.y + frame.h <= size[2])
                if position == "full" then
                    assert.are.equal(2, #widget.layout)
                    assert.are.equal(5, #widget.layout[2])
                    assert.are.equal("10/100", widget.current_page_text:text_func())
                    widget.layout[2][1].callback() -- -10 stays available
                    assert.are.equal(1, widget.curr_page)
                else
                    assert.are.equal(13, #widget.layout)
                    assert.are.equal(size[2] - 57, frame.y + frame.h)
                    for _, row in ipairs(widget.layout) do
                        local hitbox = row[1].dimen
                        assert.is_true(hitbox.y >= frame.y)
                        assert.is_true(hitbox.y + hitbox.h <= size[2] - 57)
                    end
                    for _, row in ipairs(widget.layout) do assert.are.equal(1, #row) end
                    widget.layout[1][1].callback() -- +1
                    assert.are.equal(11, widget.curr_page)
                    widget.layout[2][1].callback() -- -1
                    assert.are.equal(10, widget.curr_page)
                end
                if position ~= "full" then
                    -- A live footer hide/height change and rotation relayout the
                    -- same instance, including button gesture ranges.
                    ui.view.footer_visible = false
                    widget:paintTo(bb, 0, 0)
                    assert.are.equal(size[2], widget.skimto_frame.dimen.y + widget.skimto_frame.dimen.h)
                    ui.view.footer_visible = true
                    ui.view.footer.getHeight = function() return 91 end
                    widget:paintTo(bb, 0, 0)
                    assert.are.equal(size[2] - 91, widget.skimto_frame.dimen.y + widget.skimto_frame.dimen.h)
                    Screen.getWidth = function() return size[2] end
                    Screen.getHeight = function() return size[1] end
                    local rotated = Blitbuffer.new(size[2], size[1], Blitbuffer.TYPE_BB8)
                    widget:paintTo(rotated, 0, 0)
                    assert.are.equal(size[1] - 91, widget.skimto_frame.dimen.y + widget.skimto_frame.dimen.h)
                    for _, row in ipairs(widget.layout) do
                        assert.is_true(row[1].dimen.y + row[1].dimen.h <= size[1] - 91)
                    end
                    rotated:free()
                end
                assert.are.equal(1, history)
                assert.are.equal(position == "full" and 1 or 0, entered)
                widget:onCloseWidget()
                assert.are.equal(position == "full" and 1 or 0, exited)
                bb:free()
            end)
        end
    end
end)
