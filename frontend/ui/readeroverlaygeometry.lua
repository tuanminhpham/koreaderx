-- Geometry shared by reader overlays. The footer is a BottomContainer whose
-- content height includes separator, text, progress and bottom padding.
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Geometry = {}
function Geometry.available(ui)
    local w, h = Screen:getWidth(), Screen:getHeight()
    local footer = ui.view.footer
    if ui.view.footer_visible and footer then
        h = math.max(0, h - footer:getHeight())
    end
    return Geom:new{ x = 0, y = 0, w = w, h = h }
end
return Geometry
