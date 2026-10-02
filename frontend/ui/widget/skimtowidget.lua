local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local SkimToWidget = FocusManager:extend{}

function SkimToWidget:init()
    if self.ui.paging then -- "page" view
        self.ui.paging:enterSkimMode()
    end

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapProgress = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = screen_width,
                    h = screen_height,
                }
            },
        }
    end

    -- nil for default center full mode; "top" and "bottom" for compact mode
    local skim_dialog_position = G_reader_settings:readSetting("skim_dialog_position")
    local full_mode = not skim_dialog_position
    self.compact_mode = not full_mode

    local frame_border_size = Size.border.window
    local button_span_unit_width = Size.span.horizontal_small
    local button_font_size, button_height, frame_padding, frame_width, inner_width, nb_buttons, larger_span_units, progress_bar_height
    if full_mode then
        button_font_size = nil -- use default
        button_height = nil
        frame_padding = Size.padding.fullscreen -- large padding for airy feeling
        frame_width = math.floor(math.min(screen_width, screen_height) * 0.95)
        inner_width = frame_width - 2 * (frame_border_size + frame_padding)
        nb_buttons = 5 -- with the middle one separated a bit more from the others
        larger_span_units = 3 -- 3 x small span width
        progress_bar_height = Size.item.height_big
    else
        button_font_size = 12
        frame_padding = Size.padding.small
        frame_border_size = Size.border.thin
        button_span_unit_width = Screen:scaleBySize(2)
        -- Thirteen controls in a column. Fit the actual content to short screens.
        button_height = math.min(Screen:scaleBySize(22), math.floor(
            (screen_height - 2 * (frame_padding + frame_border_size) - 12 * button_span_unit_width) / 13))
        button_height = math.max(1, button_height)
        inner_width = button_height
        nb_buttons = 1
        larger_span_units = 1
        progress_bar_height = Screen:scaleBySize(6)
    end
    local nb_span_units = (nb_buttons - 1) - 2 + 2 * larger_span_units
    local button_width = math.floor((inner_width - nb_span_units * button_span_unit_width) * (1 / nb_buttons))
    -- Update inner_width (possibly smaller because of math.floor())
    inner_width = nb_buttons * button_width + nb_span_units * button_span_unit_width

    self.curr_page = self.ui:getCurrentPage()
    self.page_count = self.ui.document:getPageCount()

    -- Determine if we need to invert the button functionality and labels
    local invert_buttons = self.ui.view:shouldInvertBiDiLayoutMirroring()

    self.progress_bar = ProgressWidget:new{
        width = inner_width,
        height = progress_bar_height,
        percentage = self.curr_page / self.page_count,
        ticks = self.ui.toc:getTocTicksFlattened(),
        tick_width = Size.line.medium,
        last = self.page_count,
        alt = self.ui.document.flows,
        initial_pos_marker = true,
        invert_direction = invert_buttons,
    }

    -- Bottom row buttons
    local button_minus = Button:new{
        text = full_mode and "-1" or "◁",
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 1)
        end,
    }
    local button_minus_ten = Button:new{
        text = "-10",
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 10)
        end,
    }
    local button_plus = Button:new{
        text = full_mode and "+1" or "▷",
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 1)
        end,
    }
    local button_plus_ten = Button:new{
        text = "+10",
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 10)
        end,
    }
    self.current_page_text = Button:new{
        text_func = function()
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                return self.ui.pagemap:getCurrentPageLabel(true)
            end
            return tostring(self.curr_page) .. "/" .. tostring(self.page_count)
        end,
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        padding = 0,
        bordersize = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
        hold_callback = function()
            self:goToOrigPage()
        end,
    }
    local button_orig_page = Button:new{
        text = "\u{21BA}", -- Anticlockwise Open Circle Arrow
        -- text = "\u{21A9}", -- Leftwards Arrow with Hook
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToOrigPage()
        end,
    }

    -- Top row buttons
    local chapter_prev_text = "\u{2595}\u{25C1}\u{2002}" -- ▕◁ (right one eighth block, white left-pointing triangle, en space)
    local chapter_next_text = "\u{2002}\u{25B7}\u{258F}" -- ▷▏ (en space, white right-pointing triangle, left one eighth block)
    local bookmark_prev_text = "\u{F097}\u{25C1}" -- ◁ (private use area character, white left-pointing triangle)
    local bookmark_next_text = "\u{25B7}\u{F097}" -- ▷ (white right-pointing triangle, private use area character)
    local bookmark_enabled_text = "\u{F02E}"
    local bookmark_disabled_text = "\u{F097}"
    if BD.mirroredUILayout() then
        chapter_prev_text = BD.ltr(chapter_next_text)
        -- (We need this trick to keep BiDi from reordering chapter_next_text's leading space in RTL)
        chapter_next_text = "\u{2002}" .. BD.ltr("\u{2595}\u{25C1}")
        bookmark_next_text, bookmark_prev_text = BD.ltr(bookmark_prev_text), BD.ltr(bookmark_next_text)
    end
    if not full_mode then
        chapter_next_text, chapter_prev_text = "⏭", "⏮"
        bookmark_next_text, bookmark_prev_text = "➡", "⬅"
    end
    if invert_buttons then
        chapter_next_text, chapter_prev_text = chapter_prev_text, chapter_next_text
        bookmark_next_text, bookmark_prev_text = bookmark_prev_text, bookmark_next_text
    end
    local button_chapter_next = Button:new{
        text = chapter_next_text,
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getNextChapter(self.curr_page)
            if page and page >= 1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(self.page_count)
        end,
    }
    local button_chapter_prev = Button:new{
        text = chapter_prev_text,
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getPreviousChapter(self.curr_page)
            if page and page >= 1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(1)
        end,
    }
    local button_bookmark_next = Button:new{
        text = bookmark_next_text,
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToByEvent("GotoNextBookmarkFromPage")
        end,
        hold_callback = function()
            self:goToByEvent("GotoLastBookmark")
        end,
    }
    local button_bookmark_prev = Button:new{
        text = bookmark_prev_text,
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToByEvent("GotoPreviousBookmarkFromPage")
        end,
        hold_callback = function()
            self:goToByEvent("GotoFirstBookmark")
        end,
    }
    self.button_bookmark_toggle = Button:new{
        text_func = function()
            return self.ui.view.dogear_visible and bookmark_enabled_text or bookmark_disabled_text
        end,
        text_font_size = button_font_size,
        radius = full_mode and 0 or Size.radius.round,
        width = button_width,
        height = button_height,
        show_parent = self,
        callback = function()
            self.ui:handleEvent(Event:new("ToggleBookmark"))
            self:update()
        end,
        hold_callback = function()
            self.ui:handleEvent(Event:new("ShowBookmark"))
            UIManager:close(self)
        end,
    }

    local small_button_span = HorizontalSpan:new{ width = button_span_unit_width }
    local large_button_span = HorizontalSpan:new{ width = button_span_unit_width * larger_span_units }
    local top_row_span, bottom_row_span, top_buttons_row, bottom_buttons_row, radius
    local compact_buttons
    if full_mode then
        top_row_span = VerticalSpan:new{ width = Size.padding.fullscreen }
        bottom_row_span = top_row_span
        top_buttons_row = HorizontalGroup:new{
            align = "center",
            button_chapter_prev,
            small_button_span,
            button_bookmark_prev,
            large_button_span,
            self.button_bookmark_toggle,
            large_button_span,
            button_bookmark_next,
            small_button_span,
            button_chapter_next,
        }
        bottom_buttons_row = HorizontalGroup:new{
            align = "center",
            button_minus_ten,
            small_button_span,
            button_minus,
            large_button_span,
            self.current_page_text,
            large_button_span,
            button_plus,
            small_button_span,
            button_plus_ten,
        }
        radius = Size.radius.window
        if invert_buttons then
            util.arrayReverse(top_buttons_row)
            util.arrayReverse(bottom_buttons_row)
        end
    else
        local function compactButton(text, callback, hold_callback)
            return Button:new{
                text = text, text_font_size = button_font_size,
                width = button_width, height = button_height,
                radius = Size.radius.round, padding = 0,
                show_parent = self, vsync = true,
                callback = callback, hold_callback = hold_callback,
            }
        end
        local button_highlight_next = compactButton("⏩", function()
            self:goToByEvent("GotoNextHighlightPageFromPage")
        end, function() self:goToByEvent("GotoLastBookmark") end)
        local button_highlight_prev = compactButton("⏪", function()
            self:goToByEvent("GotoPreviousHighlightPageFromPage")
        end, function() self:goToByEvent("GotoFirstBookmark") end)
        self.button_ai_translate = compactButton(
            G_reader_settings:readSetting("ai_translate") == "1" and "AI" or "ai", function()
                local enabled = G_reader_settings:readSetting("ai_translate") ~= "1"
                self.ui.highlight:setAITranslateEnabled(enabled)
                self.button_ai_translate:setText(enabled and "AI" or "ai", button_width)
                self:update()
            end)
        local button_toc = compactButton("☰", function()
            UIManager:close(self)
            self.ui.toc:onShowToc()
        end)
        local button_menu = compactButton("⋮", function()
            UIManager:close(self)
            self.ui:handleEvent(Event:new("ShowMenu"))
        end)
        compact_buttons = {
            button_plus, button_minus, button_highlight_next, button_highlight_prev,
            button_bookmark_next, button_bookmark_prev, button_chapter_next, button_chapter_prev,
            self.button_bookmark_toggle, self.button_ai_translate, button_orig_page, button_toc, button_menu,
        }
        top_buttons_row = VerticalGroup:new{ align = "center" }
        for i, button in ipairs(compact_buttons) do
            if i > 1 then
                table.insert(top_buttons_row, VerticalSpan:new{ width = button_span_unit_width })
            end
            table.insert(top_buttons_row, button)
        end
        radius = Size.radius.round
    end

    -- Free controls retained for callbacks/update but absent from the visible tree.
    self.detached_buttons = full_mode and { button_orig_page }
        or { button_minus_ten, button_plus_ten, self.current_page_text }

    self.skimto_frame = FrameContainer:new{
        margin = 0,
        bordersize = frame_border_size,
        padding = frame_padding,
        radius = radius,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            top_buttons_row,
            top_row_span,
            -- The KOReaderX toolbar intentionally has no progress slider.
            bottom_row_span,
            bottom_buttons_row,
        }
    }
    self.movable = MovableContainer:new{
        self.skimto_frame,
    }
    local frame_size = self.skimto_frame:getSize()
    self[1] = WidgetContainer:new{
        align = full_mode and "center" or nil,
        dimen = full_mode and Geom:new{ x = 0, y = 0, w = screen_width, h = screen_height }
            or Geom:new{
                x = math.max(0, screen_width - frame_size.w),
                y = skim_dialog_position == "top" and 0 or math.max(0, screen_height - frame_size.h),
                w = frame_size.w, h = frame_size.h,
            },
        self.movable,
    }
    if Device:isTouchDevice() then
        local range = Geom:new{ x = 0, y = 0, w = screen_width, h = screen_height }
        self.ges_events.Hold = { GestureRange:new{ ges = "hold", range = range } }
        self.ges_events.HoldPan = { GestureRange:new{ ges = "hold_pan", range = range } }
        self.ges_events.HoldRelease = { GestureRange:new{ ges = "hold_release", range = range } }
    end

    if Device:hasDPad() then
        if full_mode then
            self.layout = {
                { button_chapter_prev, button_bookmark_prev, self.button_bookmark_toggle, button_bookmark_next, button_chapter_next },
                { button_minus_ten, button_minus, self.current_page_text, button_plus, button_plus_ten },
            }
        else
            self.layout = {}
            for _, button in ipairs(compact_buttons) do
                table.insert(self.layout, { button })
            end
        end
        -- Invert D-Pad navigation layout to match visual button order
        if invert_buttons then
            if full_mode then
                util.arrayReverse(self.layout[1])
                util.arrayReverse(self.layout[2])
            end
        end
        self:moveFocusTo(1, 1)
    end
    if Device:hasKeyboard() then
        self.key_events.QKey = { { "Q" }, event = "FirstRowKeyPress", args =    0 }
        self.key_events.WKey = { { "W" }, event = "FirstRowKeyPress", args = 0.11 }
        self.key_events.EKey = { { "E" }, event = "FirstRowKeyPress", args = 0.22 }
        self.key_events.RKey = { { "R" }, event = "FirstRowKeyPress", args = 0.33 }
        self.key_events.TKey = { { "T" }, event = "FirstRowKeyPress", args = 0.44 }
        self.key_events.YKey = { { "Y" }, event = "FirstRowKeyPress", args = 0.55 }
        self.key_events.UKey = { { "U" }, event = "FirstRowKeyPress", args = 0.66 }
        self.key_events.IKey = { { "I" }, event = "FirstRowKeyPress", args = 0.77 }
        self.key_events.OKey = { { "O" }, event = "FirstRowKeyPress", args = 0.88 }
        self.key_events.PKey = { { "P" }, event = "FirstRowKeyPress", args =    1 }
    end
end

function SkimToWidget:update()
    if self.curr_page <= 0 then
        self.curr_page = 1
    end
    if self.curr_page > self.page_count then
        self.curr_page = self.page_count
    end
    self.progress_bar.percentage = self.curr_page / self.page_count
    self.current_page_text:setText(self.current_page_text:text_func(), self.current_page_text.width)
    self.button_bookmark_toggle:setText(self.button_bookmark_toggle:text_func(), self.button_bookmark_toggle.width)
    self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK)
end

function SkimToWidget:addOriginToLocationStack()
    -- Only add the page from which we launched the SkimToWidget to the location stack
    if not self.orig_page_added_to_stack then
        self.ui.link:addCurrentLocationToStack()
        self.orig_page_added_to_stack = true
    end
end

function SkimToWidget:onCloseWidget()
    if self.ui.paging then
        self.ui.paging:exitSkimMode()
    end
    UIManager:setDirty(nil, function()
        return "ui", self.skimto_frame.dimen
    end)
    -- These objects remain alive for update(), but are absent from the widget tree.
    self.progress_bar:free()
    for _, button in ipairs(self.detached_buttons) do button:free() end
    self:free()
end

function SkimToWidget:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.skimto_frame.dimen
    end)
    return true
end

function SkimToWidget:goToOrigPage()
    if self.orig_page_added_to_stack then
        self.ui.link:onGoBackLink()
        self.curr_page = self.ui:getCurrentPage()
        self:update()
        self.orig_page_added_to_stack = nil
    end
end

function SkimToWidget:goToPage(page)
    self.curr_page = page
    self:addOriginToLocationStack()
    self.ui:handleEvent(Event:new("GotoPage", self.curr_page))
    self:update()
end

function SkimToWidget:goToByEvent(event_name)
    self:addOriginToLocationStack()
    self.ui:handleEvent(Event:new(event_name, false))
        -- add_current_location_to_stack=false, as we handled it here
    self.curr_page = self.ui:getCurrentPage()
    self:update()
end

function SkimToWidget:onFirstRowKeyPress(percent)
    local page = Math.round(percent * self.page_count)
    self:goToPage(page)
end

-- A child MovableContainer can consume a hold-pan when the pointer crosses it.
-- Keep an active page selection's continuation ahead of child event dispatch.
function SkimToWidget:handleEvent(event)
    if self._highlight_hold_active and event.handler == "onGesture" then
        local ges = event.args[1]
        if ges and ges.ges == "hold_pan" then
            return self:onHoldPan(nil, ges)
        elseif ges and ges.ges == "hold_release" then
            return self:onHoldRelease(nil, ges)
        end
    end
    return FocusManager.handleEvent(self, event)
end

-- Forward exactly once, then consume the event so UIManager does not dispatch it
-- to ReaderUI again. A hold started on the page must finish even over the toolbar.
function SkimToWidget:passGestureOutside(method, arg, ges_ev)
    local highlight = self.ui and self.ui.highlight
    if not highlight or type(highlight[method]) ~= "function" then return true end
    local inside = ges_ev and ges_ev.pos and self.skimto_frame.dimen
        and ges_ev.pos:intersectWith(self.skimto_frame.dimen)
    if method == "onHold" then
        self._highlight_hold_active = ges_ev and ges_ev.pos and not inside or nil
    end
    local holding = self._highlight_hold_active
    local continue_hold = method == "onHoldPan" or method == "onHoldRelease"
    if continue_hold then
        if holding then highlight[method](highlight, arg, ges_ev) end
        if method == "onHoldRelease" then self._highlight_hold_active = nil end
    elseif ges_ev and ges_ev.pos and not inside then
        highlight[method](highlight, arg, ges_ev)
    end
    return true
end

function SkimToWidget:onTapProgress(arg, ges_ev)
    return self:passGestureOutside("onTap", arg, ges_ev)
end

function SkimToWidget:onHold(arg, ges_ev)
    return self:passGestureOutside("onHold", arg, ges_ev)
end

function SkimToWidget:onHoldPan(arg, ges_ev)
    return self:passGestureOutside("onHoldPan", arg, ges_ev)
end

function SkimToWidget:onHoldRelease(arg, ges_ev)
    return self:passGestureOutside("onHoldRelease", arg, ges_ev)
end

function SkimToWidget:onClose()
    UIManager:close(self)
    return true
end

return SkimToWidget
