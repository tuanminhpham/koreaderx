describe("KOReaderX skim gesture forwarding", function()
    local SkimToWidget, Geom
    setup(function()
        require("commonrequire")
        SkimToWidget = require("ui/widget/skimtowidget")
        Geom = require("ui/geometry")
    end)
    it("forwards page taps once and consumes taps even when highlight returns false", function()
        local calls = 0
        local widget = setmetatable({
            skimto_frame = { dimen = Geom:new{ x = 90, y = 0, w = 10, h = 100 } },
            ui = { highlight = { onTap = function() calls = calls + 1; return false end } },
        }, { __index = SkimToWidget })
        assert.is_true(widget:onTapProgress(nil, { pos = Geom:new{ x = 10, y = 10, w = 1, h = 1 } }))
        assert.are.equal(1, calls)
        assert.is_true(widget:onTapProgress(nil, { pos = Geom:new{ x = 95, y = 10, w = 1, h = 1 } }))
        assert.is_true(widget:onTapProgress(nil, {}))
        assert.are.equal(1, calls)
    end)
    it("finishes a page selection even when its release crosses the toolbar or has no position", function()
        local calls = {}
        local widget = setmetatable({
            skimto_frame = { dimen = Geom:new{ x = 90, y = 0, w = 10, h = 100 } },
            ui = { highlight = {
                onHold = function() calls[#calls + 1] = "hold" end,
                onHoldPan = function() calls[#calls + 1] = "pan" end,
                onHoldRelease = function() calls[#calls + 1] = "release" end,
            } },
        }, { __index = SkimToWidget })
        local outside = { pos = Geom:new{ x = 10, y = 10, w = 1, h = 1 } }
        local inside = { pos = Geom:new{ x = 95, y = 10, w = 1, h = 1 } }
        widget:onHold(nil, outside)
        inside.ges = "hold_pan"
        widget:handleEvent(require("ui/event"):new("Gesture", inside))
        widget:handleEvent(require("ui/event"):new("Gesture", { ges = "hold_release" }))
        widget:onHoldRelease(nil, outside)
        assert.are.same({ "hold", "pan", "release" }, calls)
        widget:onHold(nil, inside)
        widget:onHoldPan(nil, outside)
        widget:onHoldRelease(nil, outside)
        assert.are.same({ "hold", "pan", "release" }, calls)
    end)
end)
