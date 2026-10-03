local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Geometry = require("ui/readeroverlaygeometry")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local Panel = WidgetContainer:extend{ covers_fullscreen = false }

function Panel:relayout()
    local area = Geometry.available(self.ui)
    local width = math.floor(math.min(area.w, area.h) * 2 / 3)
    local toolbar = self.ui.gotopage.skimto
    if toolbar and toolbar.skimto_frame.dimen then
        width = math.min(width, toolbar.skimto_frame.dimen.x)
    end
    local menu = self[1]
    local scale = Screen:scaleBySize(22)
    if menu.width ~= width or menu.height ~= area.h or self._scale ~= scale then
        local page = menu.page
        menu:free()
        menu.width, menu.height = width, area.h
        if menu.custom_title_bar then
            menu.custom_title_bar.width = width
            menu.custom_title_bar:init()
        end
        menu:init()
        menu.page = math.min(page, menu.page_num)
        menu:updateItems()
        self._scale = scale
    end
    -- Menu's screen-sized pagination spacing is too wide for this panel.
    local fixed = 0
    for _, button in ipairs({menu.page_info_first_chev, menu.page_info_left_chev,
            menu.page_info_text, menu.page_info_right_chev, menu.page_info_last_chev}) do
        fixed = fixed + button:getSize().w
    end
    menu.page_info_spacer.width = math.max(0, math.min(Screen:scaleBySize(32),
        math.floor((menu.inner_dimen.w - fixed) / 4)))
    menu.page_info:resetLayout()
    self.dimen = area
end

function Panel:paintTo(bb, x, y)
    self:relayout()
    self[1]:paintTo(bb, x, y)
end

function Panel:handleEvent(event)
    if event.handler == "onGesture" then
        local ges = event.args[1]
        if ges and ges.pos then
            local toolbar = self.ui.gotopage.skimto
            if toolbar and toolbar.skimto_frame.dimen
                    and ges.pos:intersectWith(toolbar.skimto_frame.dimen) then
                toolbar:handleEvent(event)
                return true
            end
            local area = Geometry.available(self.ui)
            if self.ui.view.footer_visible and ges.pos.y >= area.h then
                self.ui:handleEvent(event)
                return true
            end
            if not ges.pos:intersectWith(self[1].dimen) then
                if ges.ges == "tap" then self.dismiss() end
                -- Never replay an outside tap to page turning or selection.
                return true
            end
        end
    end
    return WidgetContainer.handleEvent(self, event)
end

function Panel:onCloseWidget()
    self.owner.toc_panel, self.owner.toc_menu = nil, nil
    self:free()
    UIManager:setDirty(self.ui, "ui")
end
return Panel
