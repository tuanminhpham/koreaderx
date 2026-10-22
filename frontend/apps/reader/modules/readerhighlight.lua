local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonSelector = require("ui/widget/buttonselector")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureDetector = require("device/gesturedetector")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local Size = require("ui/size")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local T = ffiUtil.template
local Screen = Device.screen

local ReaderHighlight = InputContainer:extend{
    -- Matches what is available in BlitBuffer.HIGHLIGHT_COLORS
    highlight_colors = {
        {_("Yellow"), "yellow"},
        {_("Green"), "green"},
        {_("Cyan"), "cyan"},
        {_("Purple"), "purple"},
    },
}

function ReaderHighlight:getHighlightColorString(color_name)
    for _, color in ipairs(self.highlight_colors) do
        if color_name == color[2] then
            return color[1]
        end
    end
    return color_name -- unknown
end

function ReaderHighlight:getHighlightColorList()
    local color_list = {}
    for i, color in ipairs(self.highlight_colors) do
        color_list[i] = self:getHighlightColor(color[2])
    end
    return color_list
end

function ReaderHighlight:getHighlightColor(color_name)
    local color = Blitbuffer.colorFromName(color_name)
    if color then
        if Screen.night_mode then
            local r, g, b = Blitbuffer.HIGHLIGHT_COLORS[color_name]:match("#(..)(..)(..)")
            return Blitbuffer.colorFromString(string.format("#%02x%02x%02x",
                255 - tonumber(r, 16), 255 - tonumber(g, 16), 255 - tonumber(b, 16)))
        end
        return color
    end
    return Blitbuffer.gray(G_reader_settings:readSetting("highlight_lighten_factor") or 0.2)
end

local function inside_box(pos, box)
    if pos then
        local x, y = pos.x, pos.y
        if box.x <= x and box.y <= y
            and box.x + box.w >= x
            and box.y + box.h >= y then
            return true
        end
    end
end

function ReaderHighlight:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.select_mode = false -- extended highlighting
    self._fallback_drawer = self.view.highlight.saved_drawer -- "lighten"
    self._fallback_color = self.view.highlight.saved_color -- "yellow" or "gray"

    self._highlight_buttons = {
        -- highlight and add_note are for the document itself,
        -- so we put them first.
        ["01_select"] = function(this, index)
            return {
                text = index and _("Extend") or _("Select"),
                enabled = not (index and this.ui.annotation.annotations[index].text_edited),
                callback = function()
                    this:startSelection(index)
                    this:onClose()
                    if not Device:isTouchDevice() then
                        self.ui.keyselection:startHighlightIndicator()
                    end
                end,
            }
        end,
        ["02_highlight"] = function(this)
            return {
                text = _("Highlight"),
                enabled = this.hold_pos ~= nil,
                callback = function()
                    this:showHighlightPrompt()
                end,
            }
        end,
        ["03_copy"] = function(this)
            return {
                text = C_("Text", "Copy"),
                enabled = Device:hasClipboard(),
                callback = function()
                    Device.input.setClipboardText(util.cleanupSelectedText(this.selected_text.text))
                    this:onClose(true)
                    UIManager:show(Notification:new{
                        text = _("Selection copied to clipboard."),
                    })
                    UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"), function()
                        this:clear()
                    end)
                end,
            }
        end,
        ["04_add_note"] = function(this)
            return {
                text = _("Add note"),
                enabled = this.hold_pos ~= nil,
                callback = function()
                    this:addNote()
                end,
            }
        end,
        -- then information lookup functions, putting on the left those that
        -- depend on an internet connection.
        ["05_wikipedia"] = function(this)
            return {
                text = _("Wikipedia"),
                callback = function()
                    UIManager:scheduleIn(0.1, function()
                        this:lookupWikipedia()
                        -- We don't call this:onClose(), we need the highlight
                        -- to still be there, as we may Highlight it from the
                        -- dict lookup widget.
                    end)
                end,
            }
        end,
        ["06_dictionary"] = function(this, index)
            return {
                text = _("Dictionary"),
                callback = function()
                    this:lookupDict(index)
                    this:onClose(true) -- keep highlight for dictionary lookup
                end,
            }
        end,
        ["07_translate"] = function(this, index)
            return {
                text = _("Translate"),
                callback = function()
                    this:translate(index)
                    -- We don't call this:onClose(), so one can still see
                    -- the highlighted text when moving the translated
                    -- text window, and also if NetworkMgr:promptWifiOn()
                    -- is needed, so the user can just tap again on this
                    -- button and does not need to select the text again.
                end,
            }
        end,
        -- buttons 08-11 are conditional ones, so the number of buttons can be even or odd
        -- let the Search button be the last, occasionally narrow or wide, less confusing
        ["12_search"] = function(this)
            return {
                text = _("Search"),
                callback = function()
                    this:onHighlightSearch()
                    -- We don't call this:onClose(), crengine will highlight
                    -- search matches on the current page, and self:clear()
                    -- would redraw and remove crengine native highlights
                end,
            }
        end,
    }

    -- Android devices
    if Device:canShareText() then
        local action = _("Share Text")
        self:addToHighlightDialog("08_share_text", function(this)
            return {
                text = action,
                callback = function()
                    local text = util.cleanupSelectedText(this.selected_text.text)
                    -- call self:onClose() before calling the android framework
                    this:onClose()
                    Device:doShareText(text, action)
                end,
            }
        end)
    end

    -- cre documents only
    if not self.document.info.has_pages then
        self:addToHighlightDialog("09_view_html", function(this)
            return {
                text = _("View HTML"),
                callback = function()
                    this:viewSelectionHTML()
                end,
            }
        end)
    end

    -- User hyphenation dict
    self:addToHighlightDialog("10_user_dict", function(this)
        return {
            text= _("Hyphenate"),
            show_in_highlight_dialog_func = function()
                return this.ui.userhyph and this.ui.userhyph:isAvailable()
                    and not this.selected_text.text:find("[ ,;-%.\n]")
            end,
            callback = function()
                this.ui.userhyph:modifyUserEntry(this.selected_text.text)
                this:onClose()
            end,
        }
    end)

    -- Links
    self:addToHighlightDialog("11_follow_link", function(this)
        return {
            text = _("Follow Link"),
            show_in_highlight_dialog_func = function()
                return this.selected_link ~= nil
            end,
            callback = function()
                local link = this.selected_link.link or this.selected_link
                this.ui.link:onGotoLink(link)
                this:onClose()
            end,
        }
    end)

    self.ui:registerPostInitCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)

    -- delegate gesture listener to readerui, NOP our own
    self.ges_events = nil
end

function ReaderHighlight:onSetDimensions(dimen)
    self.screen_w, self.screen_h = dimen.w, dimen.h
end

function ReaderHighlight:onGesture() end

function ReaderHighlight:setupTouchZones()
    if not Device:isTouchDevice() then return end
    local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate")
    if not hold_pan_rate then
        hold_pan_rate = Screen.low_pan_rate and 5.0 or 30.0
    end
    local DTAP_ZONE_TOP_LEFT = G_defaults:readSetting("DTAP_ZONE_TOP_LEFT")
    self.ui:registerTouchZones({
        {
            id = "readerhighlight_tap_select_mode",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_TOP_LEFT.x, ratio_y = DTAP_ZONE_TOP_LEFT.y,
                ratio_w = DTAP_ZONE_TOP_LEFT.w, ratio_h = DTAP_ZONE_TOP_LEFT.h,
            },
            overrides = {
                "readerhighlight_tap",
                "tap_top_left_corner",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onTapSelectModeIcon() end
        },
        {
            id = "readerhighlight_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            overrides = {
                -- Tap on existing highlights have priority over
                -- everything but tap on links (as links can be
                -- part of some highlighted text)
                "tap_top_left_corner",
                "tap_top_right_corner",
                "tap_left_bottom_corner",
                "tap_right_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onTap(nil, ges) end
        },
        {
            id = "readerhighlight_hold",
            ges = "hold",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onHold(nil, ges) end
        },
        {
            id = "readerhighlight_hold_release",
            ges = "hold_release",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function() return self:onHoldRelease() end
        },
        {
            id = "readerhighlight_hold_pan",
            ges = "hold_pan",
            rate = hold_pan_rate,
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onHoldPan(nil, ges) end
        },
    })
end

function ReaderHighlight:onReaderReady()
    self:setupTouchZones()
    self:onPdfAnnotationsReady()
    if self.document.is_pdf and G_reader_settings:isTrue("highlight_write_into_pdf_notify") then
        UIManager:show(Notification:new{
            text = T(_("Write highlights into PDF: %1"), self.highlight_write_into_pdf and _("on") or _("off")),
        })
    end
end

local highlight_style = {
    {_("Lighten"), "lighten"},
    {_("Underline"), "underscore"},
    {_("Strikethrough"), "strikeout"},
    {_("Invert"), "invert"},
}

local note_mark = {
    {_("None"), "none"},
    {_("Underline"), "underline"},
    {_("Side line"), "sideline"},
    {_("Side mark"), "sidemark"},
}

local long_press_action = {
    {_("Ask with popup dialog"), "ask"},
    {_("Do nothing"), "nothing"},
    {_("Highlight"), "highlight"},
    {_("Select and highlight"), "select"},
    {_("Add note"), "note"},
    {_("Translate"), "translate"},
    {_("Wikipedia"), "wikipedia"},
    {_("Dictionary"), "dictionary"},
    {_("Fulltext search"), "search"},
    {_("AI Translate"), "ai_translate"},
}
-- we need to expose this table to readerkeyselection
-- as here it is hidden under a isTouchDevice cap
ReaderHighlight.long_press_action = long_press_action

local highlight_prompt = {
    {_("none"), nil},
    {_("style"), "style"},
    {_("color"), "color"},
    {_("style, color"), "all"},
}

local highlight_dialog_position = {
    {_("Top"), "top"},
    {_("Center"), "center"},
    {_("Bottom"), "bottom"},
    {_("Highlight position"), "gesture"},
}

function ReaderHighlight:addToMainMenu(menu_items)
    -- main menu Typeset
    local star = "   ★"
    local hl_sub_item_table = {}
    menu_items.highlight_options = {
        text = _("Highlights"),
        sub_item_table = hl_sub_item_table,
    }
    for _, v in ipairs(highlight_style) do
        local style_text, style = unpack(v)
        table.insert(hl_sub_item_table, {
            text_func = function()
                return style == (G_reader_settings:readSetting("highlight_drawing_style") or self._fallback_drawer)
                    and style_text .. star or style_text
            end,
            checked_func = function()
                return self.view.highlight.saved_drawer == style
            end,
            radio = true,
            callback = function()
                self.view.highlight.saved_drawer = style
                self:setSelectionColor()
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("highlight_drawing_style", style)
                touchmenu_instance:updateItems()
            end,
        })
    end
    hl_sub_item_table[#highlight_style].separator = true
    table.insert(hl_sub_item_table, {
        text_func = function()
            local saved_color = self.view.highlight.saved_color
            local text
            for _, v in ipairs(self.highlight_colors) do
                if v[2] == saved_color then
                    text = v[1]:lower()
                    break
                end
            end
            text = text or saved_color -- nonstandard color
            local default_color = G_reader_settings:readSetting("highlight_color") or self._fallback_color
            if saved_color == default_color then
                text = text .. star
            end
            return T(_("Highlight color: %1"), text)
        end,
        enabled_func = function()
            return self.view.highlight.saved_drawer ~= "invert"
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance) -- set color for new highlights in this book
            UIManager:show(ButtonSelector:new{
                current_value = self.view.highlight.saved_color,
                values = self.highlight_colors,
                bg_colors = self:getHighlightColorList(),
                callback = function(value)
                    self:setDefaultHighlightColor(value)
                    touchmenu_instance:updateItems()
                end,
            })
        end,
        hold_callback = function(touchmenu_instance) -- set color for new highlights in new books
            G_reader_settings:saveSetting("highlight_color", self.view.highlight.saved_color)
            touchmenu_instance:updateItems()
        end,
    })
    table.insert(hl_sub_item_table, {
        text_func = function()
            return T(_("Gray highlight opacity: %1"), G_reader_settings:readSetting("highlight_lighten_factor", 0.2))
        end,
        enabled_func = function()
            return self.view.highlight.saved_drawer == "lighten"
        end,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                value = G_reader_settings:readSetting("highlight_lighten_factor"),
                value_min = 0,
                value_max = 1,
                precision = "%.2f",
                value_step = 0.1,
                value_hold_step = 0.05,
                default_value = 0.2,
                keep_shown_on_apply = true,
                title_text = _("Gray highlight opacity"),
                info_text = _("The higher the value, the darker the gray."),
                callback = function(spin)
                    G_reader_settings:saveSetting("highlight_lighten_factor", spin.value)
                    self.view.highlight.lighten_factor = spin.value
                    UIManager:setDirty(self.dialog, "ui")
                    touchmenu_instance:updateItems()
                end,
            })
        end,
    })
    table.insert(hl_sub_item_table, {
        text = _("Use highlight color for selection"),
        enabled_func = function()
            return self.view.highlight.saved_drawer ~= "invert"
        end,
        checked_func = function()
            return self.view.highlight.saved_drawer ~= "invert" and G_reader_settings:isTrue("highlight_selection_use_highlight_color")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("highlight_selection_use_highlight_color")
            self:setSelectionColor()
        end,
    })
    table.insert(hl_sub_item_table, {
        text_func = function()
            return T(_("Gray selection opacity: %1"), G_reader_settings:readSetting("highlight_selection_lighten_factor") or 0.2)
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                value = G_reader_settings:readSetting("highlight_selection_lighten_factor") or 0.2,
                value_min = 0,
                value_max = 1,
                precision = "%.2f",
                value_step = 0.1,
                value_hold_step = 0.05,
                default_value = 0.2,
                title_text = _("Gray selection opacity"),
                info_text = _("The higher the value, the darker the gray."),
                callback = function(spin)
                    local value = spin.value ~= 0.2 and spin.value or nil
                    G_reader_settings:saveSetting("highlight_selection_lighten_factor", value)
                    self:setSelectionColor()
                    touchmenu_instance:updateItems()
                end,
            })
        end,
        separator = true,
    })
    table.insert(hl_sub_item_table, {
        text_func = function()
            return T(_("Highlight line height: %1\xE2\x80\xAF%"), G_reader_settings:readSetting("highlight_height_pct") or 100)
        end,
        enabled_func = function()
            return self.view.highlight.saved_drawer == "lighten" or self.view.highlight.saved_drawer == "invert"
        end,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                value = G_reader_settings:readSetting("highlight_height_pct") or 100,
                value_min = 0,
                value_max = 100,
                value_step = 1,
                value_hold_step = 10,
                default_value = 100,
                unit = "%",
                keep_shown_on_apply = true,
                title_text = _("Highlight line height"),
                info_text = _("Percentage of the text line height."),
                callback = function(spin)
                    local value = spin.value ~= 100 and spin.value or nil
                    G_reader_settings:saveSetting("highlight_height_pct", value)
                    UIManager:setDirty(self.dialog, "ui")
                    touchmenu_instance:updateItems()
                end,
            })
        end,
    })
    table.insert(hl_sub_item_table, {
        text_func = function()
            local notemark = self.view.highlight.note_mark or "none"
            for __, v in ipairs(note_mark) do
                if v[2] == notemark then
                    return T(_("Note marker: %1"), v[1]:lower())
                end
            end
        end,
        callback = function()
            UIManager:show(ButtonSelector:new{
                current_value = self.view.highlight.note_mark or "none",
                values = note_mark,
                keep_open_on_apply = true,
                callback = function(value)
                    self.view.highlight.note_mark = value ~= "none" and value or nil
                    G_reader_settings:saveSetting("highlight_note_marker", self.view.highlight.note_mark)
                    self.view:setupNoteMarkPosition()
                    UIManager:setDirty(self.dialog, "ui")
                end,
            })
        end,
        separator = true,
    })
    table.insert(hl_sub_item_table, {
        text = _("Apply current style and color to all highlights"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to update all highlights?"),
                icon = "texture-box",
                ok_callback = function()
                    local count = self:applyCurrentHighlightStyleAndColor()
                    if count > 0 then
                        UIManager:setDirty(self.dialog, "ui")
                        UIManager:show(Notification:new{
                            text = T(N_("Applied style and color to 1 highlight",
                                "Applied style and color to %1 highlights", count), count),
                        })
                    end
                end,
            })
        end,
        separator = self.ui.paging and true,
    })
    if self.document.is_pdf then
        table.insert(hl_sub_item_table, {
            text_func = function()
                local text = self.highlight_write_into_pdf and _("on") or _("off")
                if (not self.highlight_write_into_pdf) == (not G_reader_settings:isTrue("highlight_write_into_pdf")) then
                    text = text .. star
                end
                return T(_("Write highlights into PDF: %1"), text)
            end,
            sub_item_table = {
                {
                    text_func = function()
                        local text = _("On")
                        return G_reader_settings:isTrue("highlight_write_into_pdf") and text .. star or text
                    end,
                    checked_func = function()
                        return self.highlight_write_into_pdf
                    end,
                    radio = true,
                    callback = function()
                        if self.document:_checkIfWritable() then
                            self.highlight_write_into_pdf = true
                            if G_reader_settings:readSetting("document_metadata_folder") == "hash" then
                                UIManager:show(InfoMessage:new{
                                    text = _("Warning: Book metadata location is set to hash-based storage. Writing highlights into a PDF modifies the file which may change the partial hash, resulting in its metadata (e.g., highlights and progress) being unlinked and lost."),
                                    icon = "notice-warning",
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                            text = _([[
Highlights in this document will be saved in the settings file, but they won't be written in the document itself because the file is in a read-only location.

If you wish your highlights to be saved in the document, just move it to a writable directory first.]]),
                            })
                        end
                    end,
                    hold_callback = function(touchmenu_instance)
                        G_reader_settings:makeTrue("highlight_write_into_pdf")
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text_func = function()
                        local text = _("Off")
                        return G_reader_settings:hasNot("highlight_write_into_pdf") and text .. star or text
                    end,
                    checked_func = function()
                        return not self.highlight_write_into_pdf
                    end,
                    radio = true,
                    callback = function()
                        self.highlight_write_into_pdf = false
                    end,
                    hold_callback = function(touchmenu_instance)
                        G_reader_settings:delSetting("highlight_write_into_pdf")
                        touchmenu_instance:updateItems()
                    end,
                },
                {
                    text = _("Show reminder on book opening"),
                    checked_func = function()
                        return G_reader_settings:isTrue("highlight_write_into_pdf_notify")
                    end,
                    callback = function()
                        G_reader_settings:flipNilOrFalse("highlight_write_into_pdf_notify")
                    end,
                    separator = true,
                },
                {
                    text = _("Write all highlights into PDF file"),
                    enabled_func = function()
                        if not self.highlight_write_into_pdf then return false end
                        local highlights, notes = self.ui.annotation:getNumberOfHighlightsAndNotes()
                        return highlights + notes > 0
                    end,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to write all KOReader highlights into PDF file?"),
                            icon = "texture-box",
                            ok_callback = function()
                                if not self:checkAnnotationEditingAllowed() then return end
                                local count = 0
                                for _, item in ipairs(self.ui.annotation.annotations) do
                                    if item.drawer then
                                        if item.koreaderx_pdf_source then
                                            local index = self.ui.annotation:getItemIndex(item)
                                            if not self:commitImportedChange(index, util.tableDeepCopy(item), "all") then break end
                                        else
                                            if self:writePdfAnnotation("replace", item, nil, util.tableDeepCopy(item)) == false then break end
                                        end
                                        count = count + 1
                                    end
                                end
                                UIManager:show(Notification:new{
                                    text = T(N_("1 highlight written into PDF file",
                                        "%1 highlights written into PDF file", count), count),
                                })
                            end,
                        })
                    end,
                },
                {
                    text = _("Delete all highlights from PDF file"),
                    enabled_func = function()
                        if not self.highlight_write_into_pdf then return false end
                        local highlights, notes = self.ui.annotation:getNumberOfHighlightsAndNotes()
                        return highlights + notes > 0
                    end,
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to delete all KOReader highlights from PDF file?"),
                            icon = "texture-box",
                            ok_callback = function()
                                if not self:checkAnnotationEditingAllowed() then return end
                                local count = 0
                                for index = #self.ui.annotation.annotations, 1, -1 do
                                    local item = self.ui.annotation.annotations[index]
                                    if item.drawer then
                                        if item.koreaderx_pdf_source then
                                            if not self:commitImportedChange(index, util.tableDeepCopy(item), "detach") then break end
                                        elseif self:writePdfAnnotation("delete", item) == false then break end
                                        count = count + 1
                                    end
                                end
                                UIManager:show(Notification:new{
                                    text = T(N_("1 highlight deleted from PDF file",
                                        "%1 highlights deleted from PDF file", count), count),
                                })
                            end,
                        })
                    end,
                },
            },
        })
    end

    if self.ui.paging then
        menu_items.panel_zoom_options = {
            text = _("Panel zoom (manga/comic)"),
            sub_item_table = self:genPanelZoomMenu(),
        }
    end

    if self.document.supportsEmbeddedAnnotations and self.document:supportsEmbeddedAnnotations() then
        table.insert(hl_sub_item_table, {
            text = _("Import embedded PDF annotations"),
            enabled_func = function() return self.document.configurable.text_wrap == 0 end,
            callback = function() self:requestPdfImport() end,
        })
        table.insert(hl_sub_item_table, {
            text = _("Replace KOReader highlights from PDF…"),
            enabled_func = function() return self.document.configurable.text_wrap == 0 end,
            callback = function() self:resetMetadatafile() end,
        })
        table.insert(hl_sub_item_table, {
            text = _("Reimport locally deleted PDF annotations…"),
            enabled_func = function() return self.document.configurable.text_wrap == 0 end,
            callback = function() self:reimportDeletedPdfAnnotations() end,
        })
    end
    -- main menu Settings
    menu_items.long_press = {
        text = _("Long-press on text"),
        sub_item_table = {
            {
                text = _("Dictionary on single word selection"),
                checked_func = function()
                    return not self.view.highlight.disabled and G_reader_settings:nilOrFalse("highlight_action_on_single_word")
                end,
                enabled_func = function()
                    return not self.view.highlight.disabled
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("highlight_action_on_single_word")
                end,
                separator = true,
            },
        },
    }
    -- actions
    for i, v in ipairs(long_press_action) do
        table.insert(menu_items.long_press.sub_item_table, {
            text = v[1],
            checked_func = function()
                return G_reader_settings:readSetting("default_highlight_action", "ask") == v[2]
            end,
            radio = true,
            callback = function()
                self:onSetHighlightAction(i, true) -- no notification
            end,
        })
    end
    -- highlight dialog position
    local position_sub_item_table = {}
    for i, v in ipairs(highlight_dialog_position) do
        position_sub_item_table[i] = {
            text = v[1],
            checked_func = function()
                return G_reader_settings:readSetting("highlight_dialog_position", "center") == v[2]
            end,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting("highlight_dialog_position", v[2])
            end,
        }
    end
    table.insert(menu_items.long_press.sub_item_table, {
        text_func = function()
            local position = G_reader_settings:readSetting("highlight_dialog_position", "center")
            for __, v in ipairs(highlight_dialog_position) do
                if v[2] == position then
                    return T(_("Highlight dialog position: %1"), v[1]:lower())
                end
            end
        end,
        sub_item_table = position_sub_item_table,
    })
    -- highlight prompt
    local prompt_sub_item_table = {}
    for i, v in ipairs(highlight_prompt) do
        prompt_sub_item_table[i] = {
            text = v[1],
            checked_func = function()
                return G_reader_settings:readSetting("highlight_prompt") == v[2]
            end,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting("highlight_prompt", v[2])
            end,
        }
    end
    table.insert(menu_items.long_press.sub_item_table, {
        text_func = function()
            local prompt = G_reader_settings:readSetting("highlight_prompt")
            for __, v in ipairs(highlight_prompt) do
                if v[2] == prompt then
                    return T(_("Highlight prompt: %1"), v[1])
                end
            end
        end,
        sub_item_table = prompt_sub_item_table,
    })
    if Device:isTouchDevice() then
        -- highlight very-long-press interval
        table.insert(menu_items.long_press.sub_item_table, {
            text_func = function()
                return T(_("Highlight very-long-press interval: %1 s"),
                    G_reader_settings:readSetting("highlight_long_hold_threshold_s") or GestureDetector.LONG_HOLD_INTERVAL_S)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = _("Highlight very-long-press interval"),
                    info_text = _("If a long-press is not released in this interval, it is considered a very-long-press. On document text, single word selection will not be triggered."),
                    width = math.floor(self.screen_w * 0.75),
                    value = G_reader_settings:readSetting("highlight_long_hold_threshold_s") or GestureDetector.LONG_HOLD_INTERVAL_S,
                    value_min = (G_reader_settings:readSetting("ges_hold_interval_ms")
                        or GestureDetector.HOLD_INTERVAL_MS) / 1000 + 0.1,
                    value_max = 20,
                    value_step = 0.1,
                    value_hold_step = 0.5,
                    unit = C_("Time", "s"),
                    precision = "%0.1f",
                    ok_text = _("Set interval"),
                    default_value = GestureDetector.LONG_HOLD_INTERVAL_S,
                    callback = function(spin)
                        local value = spin.value ~= GestureDetector.LONG_HOLD_INTERVAL_S and spin.value or nil
                        G_reader_settings:saveSetting("highlight_long_hold_threshold_s", value)
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        })
    end

    table.insert(menu_items.long_press.sub_item_table, {
        text = _("Auto-scroll when selection reaches a corner"),
        help_text = _([[
Auto-scroll to show part of the previous page when your text selection reaches the top left corner, or of the next page when it reaches the bottom right corner.
Except when in two columns mode, where this is limited to showing only the previous or next column.]]),
        separator = true,
        checked_func = function()
            if self.ui.paging then return false end
            return not self.view.highlight.disabled and G_reader_settings:nilOrTrue("highlight_corner_scroll")
        end,
        enabled_func = function()
            if self.ui.paging then return false end
            return not self.view.highlight.disabled
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("highlight_corner_scroll")
            self.allow_corner_scroll = G_reader_settings:nilOrTrue("highlight_corner_scroll")
        end,
    })

    -- main menu Search
    menu_items.translation_settings = Translator:genSettingsMenu()
    menu_items.translate_current_page = {
        text = _("Translate current page"),
        callback = function()
            self:onTranslateCurrentPage()
        end,
    }
end

function ReaderHighlight:genPanelZoomMenu()
    return {
        {
            text = _("Allow panel zoom"),
            checked_func = function()
                return self.panel_zoom_enabled
            end,
            callback = function()
                self:onTogglePanelZoomSetting()
            end,
            hold_callback = function()
                local ext = util.getFileNameSuffix(self.ui.document.file)
                local curr_val = G_reader_settings:getSettingForExt("panel_zoom_enabled", ext)
                G_reader_settings:saveSettingForExt("panel_zoom_enabled", not curr_val, ext)
            end,
            separator = true,
        },
        {
            text = _("Fall back to text selection"),
            checked_func = function()
                return self.panel_zoom_fallback_to_text_selection
            end,
            callback = function()
                self:onToggleFallbackTextSelection()
            end,
            hold_callback = function()
                local ext = util.getFileNameSuffix(self.ui.document.file)
                G_reader_settings:saveSettingForExt("panel_zoom_fallback_to_text_selection", self.panel_zoom_fallback_to_text_selection, ext)
            end,
            separator = true,
        },
    }
end

-- Returns a unique id, that can be provided on delayed call to :clear(id)
-- to ensure current highlight has not already been cleared, and that we
-- are not going to clear a new highlight
function ReaderHighlight:getClearId()
    self.clear_id = UIManager:getTime() -- can act as a unique id
    return self.clear_id
end

function ReaderHighlight:clear(clear_id)
    if clear_id then -- should be provided by delayed call to clear()
        if clear_id ~= self.clear_id then
            -- if clear_id is no longer valid, highlight has already been
            -- cleared since this clear_id was given
            return
        end
    end
    self.clear_id = nil -- invalidate id
    if not self.ui.document then
        -- might happen if scheduled and run after document is closed
        return
    end
    if self.ui.paging then
        self.view.highlight.temp = {}
    else
        self.ui.document:clearSelection()
    end
    if self.restore_page_mode_func then
        self.restore_page_mode_func()
        self.restore_page_mode_func = nil
    end
    self.is_word_selection = false
    self.selected_text_start_xpointer = nil
    if self.hold_pos then
        self.hold_pos = nil
        self.selected_text = nil
        UIManager:setDirty(self.dialog, "ui")
        return true
    end
end

function ReaderHighlight:onClearHighlight()
    self:clear()
    return true
end

function ReaderHighlight:onTapSelectModeIcon()
    if not self.select_mode then return end
    UIManager:show(ConfirmBox:new{
        text = _("You are currently in SELECT mode.\nTo finish highlighting, long press where the highlight should end and press the HIGHLIGHT button.\nYou can also exit select mode by tapping on the start of the highlight."),
        icon = "texture-box",
        ok_text = _("Exit select mode"),
        cancel_text = _("Close"),
        ok_callback = function()
            self.select_mode = false
            if self.ui.annotation.annotations[self.highlight_idx].is_tmp then
                self:deleteHighlight(self.highlight_idx)
            else
                UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
            end
        end,
    })
    return true
end

function ReaderHighlight:onTap(_, ges)
    if self.hold_pos then -- accidental tap while long-pressing
        return self:onHoldRelease()
    end
    if ges and #self.view.highlight.visible_boxes > 0 then
        local pos = self.view:screenToPageTransform(ges.pos)
        local highlights_tapped, highlights_added = {}, {}
        for _, box in ipairs(self.view.highlight.visible_boxes) do
            if inside_box(pos, box.rect) then
                if self.select_mode then
                    if box.index == self.highlight_idx then
                        -- tap on the first fragment: abort select mode, clear highlight
                        self.select_mode = false
                        if self.ui.annotation.annotations[box.index].is_tmp then
                            self:deleteHighlight(box.index)
                        else
                            UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
                        end
                        return true
                    end
                elseif not highlights_added[box.index] then
                    -- a highlight may contain overlapping boxes, avoid double adding
                    highlights_added[box.index] = true
                    table.insert(highlights_tapped, box.index)
                end
            end
        end
        if #highlights_tapped > 0 then
            return self:showChooseHighlightDialog(highlights_tapped)
        end
    end
end

function ReaderHighlight:getHighlightVisibleBoxes(index)
    local boxes = {}
    for _, box in ipairs(self.view.highlight.visible_boxes) do
        if box.index == index then
            table.insert(boxes, box.rect)
        end
    end
    if next(boxes) ~= nil then
        return boxes
    end
end

function ReaderHighlight:updateHighlight(index, side, direction, move_by_char)
    if not self:checkAnnotationEditingAllowed() then return false end
    if move_by_char and self.ui.paging then return end
    local highlight = util.tableDeepCopy(self.ui.annotation.annotations[index])
    local highlight_before = util.tableDeepCopy(highlight)
    local is_updated
    if self.ui.rolling then
        is_updated = self:updateHighlightRolling(highlight, side, direction, move_by_char)
    else
        is_updated = self:updateHighlightPaging(highlight, side, direction)
    end
    if is_updated then
        highlight.text = util.cleanupSelectedText(highlight.text)
        if highlight.koreaderx_pdf_source then
            local committed, updated_index = self:commitImportedChange(index, highlight, "geometry")
            if committed then
                local endpoint = side == 0 and highlight.pos0 or highlight.pos1
                if self.ui.paging.current_page ~= endpoint.page then
                    self.ui:handleEvent(Event:new("GotoPage", endpoint.page))
                end
            end
            return committed, updated_index
        end
        return self:commitOrdinaryChange(index, highlight, highlight_before)
    end
end

function ReaderHighlight:updateHighlightRolling(highlight, side, direction, move_by_char)
    local highlight_beginning = highlight.pos0
    local highlight_end = highlight.pos1
    if side == 0 then -- we move pos0
        local updated_highlight_beginning
        if direction == 1 then -- move highlight to the right
            if move_by_char then
                updated_highlight_beginning = self.ui.document:getNextVisibleChar(highlight_beginning)
            else
                updated_highlight_beginning = self.ui.document:getNextVisibleWordStart(highlight_beginning)
            end
        else -- move highlight to the left
            if move_by_char then
                updated_highlight_beginning = self.ui.document:getPrevVisibleChar(highlight_beginning)
            else
                updated_highlight_beginning = self.ui.document:getPrevVisibleWordStart(highlight_beginning)
            end
        end
        if updated_highlight_beginning == nil then return end
        local order = self.ui.document:compareXPointers(updated_highlight_beginning, highlight_end)
        if order == nil or order <= 0 then return end -- only if beginning did not go past end
        highlight.pos0 = updated_highlight_beginning
        highlight.page = updated_highlight_beginning
        highlight.chapter = self.ui.toc:getTocTitleByPage(updated_highlight_beginning)
        highlight.pageno = self.document:getPageFromXPointer(updated_highlight_beginning)
    else -- we move pos1
        local updated_highlight_end
        if direction == 1 then -- move highlight to the right
            if move_by_char then
                updated_highlight_end = self.ui.document:getNextVisibleChar(highlight_end)
            else
                updated_highlight_end = self.ui.document:getNextVisibleWordEnd(highlight_end)
            end
        else -- move highlight to the left
            if move_by_char then
                updated_highlight_end = self.ui.document:getPrevVisibleChar(highlight_end)
            else
                updated_highlight_end = self.ui.document:getPrevVisibleWordEnd(highlight_end)
            end
        end
        if updated_highlight_end == nil then return end
        local order = self.ui.document:compareXPointers(highlight_beginning, updated_highlight_end)
        if order == nil or order <= 0 then return end -- only if end did not go back past beginning
        highlight.pos1 = updated_highlight_end
    end

    local new_beginning = highlight.pos0
    local new_end = highlight.pos1
    highlight.text = self.ui.document:getTextFromXPointers(new_beginning, new_end)
    if side == 0 then
        -- Ensure we show the page with the new beginning of highlight
        if not self.ui.document:isXPointerInCurrentPage(new_beginning) then
            self.ui:handleEvent(Event:new("GotoXPointer", new_beginning))
        end
    else
        -- Ensure we show the page with the new end of highlight
        if not self.ui.document:isXPointerInCurrentPage(new_end) then
            if self.view.view_mode == "page" then
                self.ui:handleEvent(Event:new("GotoXPointer", new_end))
            else
                -- Not easy to get the y that would show the whole line
                -- containing new_end. So, we scroll so that new_end
                -- is at 2/3 of the screen.
                local end_y = self.ui.document:getPosFromXPointer(new_end)
                local top_y = end_y - math.floor(self.screen_h * 2/3)
                self.ui.rolling:_gotoPos(top_y)
            end
        end
    end
    return true
end

function ReaderHighlight:updateImportedHighlightPaging(highlight, side, direction)
    local page = self.ui.paging.current_page
    if highlight.ext and ((page ~= highlight.pos0.page and page ~= highlight.pos1.page)
        or (page == highlight.pos0.page and side == 1) or (page == highlight.pos1.page and side == 0)) then return end
    local boxes = self.document:getTextBoxes(page)
    if not boxes or #boxes == 0 then return end
    local kopt = self.document.koptinterface
    local part = highlight.ext and highlight.ext[page] or highlight
    local i0, j0 = kopt:getWordBoxIndices(boxes, part.pos0)
    local i1, j1 = kopt:getWordBoxIndices(boxes, part.pos1)
    if not (i0 and i1) then return end
    if i0 > i1 or (i0 == i1 and j0 > j1) then i0, i1, j0, j1 = i1, i0, j1, j0 end
    -- Shrinking the last word of an endpoint fragment removes that page from
    -- the logical range. The complete candidate is committed by updateHighlight;
    -- native source parts must stay intact until that transaction succeeds.
    if highlight.ext and i0 == i1 and j0 == j1
        and ((side == 0 and direction == 1) or (side == 1 and direction == -1)) then
        local next_page = page + direction
        local adjacent = highlight.ext[next_page]
        local adjacent_boxes = adjacent and self.document:getTextBoxes(next_page)
        if not (adjacent and adjacent_boxes and adjacent_boxes[1] and adjacent_boxes[1][1]) then return end
        local pos0 = util.tableDeepCopy(side == 0 and adjacent.pos0 or highlight.pos0)
        local pos1 = util.tableDeepCopy(side == 1 and adjacent.pos1 or highlight.pos1)
        if pos0.page > pos1.page then return end
        if pos0.page == pos1.page then
            local a, b = kopt:getWordBoxIndices(adjacent_boxes, pos0)
            local c, d = kopt:getWordBoxIndices(adjacent_boxes, pos1)
            if not (a and c) or a > c or (a == c and b > d) then return end
        end
        local ext, text, single_boxes = {}, {}, nil
        for number = pos0.page, pos1.page do
            local fragment = highlight.ext[number]
            local page_boxes = fragment and self.document:getTextBoxes(number)
            -- A gap without text/geometry needs a separate PDF/render contract.
            -- Keep this operation atomic rather than creating an empty quad.
            if not (fragment and page_boxes and page_boxes[1] and page_boxes[1][1]) then return end
            local selected = kopt:getTextFromNativePositions(self.document, page_boxes, fragment.pos0, fragment.pos1)
            if not (selected and selected.pboxes and #selected.pboxes > 0) then return end
            ext[number] = {pos0 = util.tableDeepCopy(fragment.pos0), pos1 = util.tableDeepCopy(fragment.pos1),
                pboxes = selected.pboxes}
            text[#text + 1] = selected.text or ""
            single_boxes = selected.pboxes
        end
        pos0.zoom, pos0.rotation = highlight.pos0.zoom, highlight.pos0.rotation
        pos1.zoom, pos1.rotation = highlight.pos1.zoom, highlight.pos1.rotation
        highlight.pos0, highlight.pos1 = pos0, pos1
        highlight.page = pos0.page
        highlight.text = table.concat(text, " ")
        highlight.ext = pos0.page ~= pos1.page and ext or nil
        highlight.pboxes = pos0.page == pos1.page and single_boxes or nil
        return true
    end
    local i, j = side == 0 and i0 or i1, side == 0 and j0 or j1
    j = j + direction
    if j < 1 then
        i = i - 1
        if i < 1 then return end
        j = #boxes[i]
    elseif j > #boxes[i] then
        i = i + 1
        if i > #boxes then return end
        j = 1
    end
    if side == 0 then
        if i > i1 or (i == i1 and j > j1) then return end
        i0, j0 = i, j
    else
        if i < i0 or (i == i0 and j < j0) then return end
        i1, j1 = i, j
    end
    local start, finish = boxes[i0][j0], boxes[i1][j1]
    if not (start and finish) then return end
    part.pos0.x, part.pos0.y = (start.x0 + start.x1) / 2, (start.y0 + start.y1) / 2
    part.pos1.x, part.pos1.y = (finish.x0 + finish.x1) / 2, (finish.y0 + finish.y1) / 2
    local selected = kopt:getTextFromNativePositions(self.document, boxes, part.pos0, part.pos1)
    if not (selected and selected.pboxes and #selected.pboxes > 0) then return end
    part.pboxes = selected.pboxes
    if highlight.ext then
        if side == 0 then highlight.pos0 = util.tableDeepCopy(part.pos0)
        else highlight.pos1 = util.tableDeepCopy(part.pos1) end
        local text = {}
        for number = highlight.pos0.page, highlight.pos1.page do
            local fragment = highlight.ext[number]
            local fragment_boxes = self.document:getTextBoxes(number)
            local selection = kopt:getTextFromNativePositions(self.document, fragment_boxes, fragment.pos0, fragment.pos1)
            text[#text + 1] = selection.text or ""
        end
        highlight.text = table.concat(text, " ")
    else
        highlight.text = selected.text or ""
    end
    return true
end

function ReaderHighlight:updateHighlightPaging(highlight, side, direction)
    if highlight.koreaderx_pdf_source then return self:updateImportedHighlightPaging(highlight, side, direction) end
    local page = self.ui.paging.current_page
    local pboxes
    if highlight.ext then -- multipage highlight, don't move invisible boundaries
        if (page ~= highlight.pos0.page and page ~= highlight.pos1.page ) or -- middle pages
                (page == highlight.pos0.page and side == 1) or -- first page, tried to move end
                (page == highlight.pos1.page and side == 0) then -- last page, tried to move start
            return
        end
        pboxes = highlight.ext[page].pboxes
    else
        pboxes = highlight.pboxes
    end
    local page_boxes = self.document:getTextBoxes(page)

    -- find page boxes indices of the highlight start and end pboxes
    -- pboxes { x, y, h, w }; page_boxes { x0, y0, x1, y1, word }
    local start_i, start_j, end_i, end_j
    local function is_equal(a, b)
        return math.abs(a - b) < 0.001
    end
    local start_box = pboxes[1]
    local end_box = pboxes[#pboxes]
    for i, line in ipairs(page_boxes) do
        for j, box in ipairs(line) do
            if not start_i and is_equal(start_box.x, box.x0) and is_equal(start_box.y, box.y0) then
                start_i, start_j = i, j
            end
            if not end_i and is_equal(end_box.x + end_box.w, box.x1) and is_equal(end_box.y, box.y0) then
                end_i, end_j = i, j
            end
            if start_i and end_i then break end
        end
        if start_i and end_i then break end
    end
    if not (start_i and end_i) then return end

    -- move
    local new_start_i, new_start_j, new_end_i, new_end_j
    if side == 0 then -- we move pos0
        new_end_i, new_end_j = end_i, end_j
        if direction == 1 then -- move highlight to the right
            if start_i == end_i and start_j == end_j then return end -- don't move start behind end
            if start_j == #page_boxes[start_i] then -- last box of the line
                new_start_i = start_i + 1
                new_start_j = 1
                table.remove(pboxes, 1)
            else
                new_start_i = start_i
                new_start_j = start_j + 1
                pboxes[1].x = page_boxes[new_start_i][new_start_j].x0
                local last_box_j = new_start_i == new_end_i and new_end_j or #page_boxes[new_start_i]
                local last_box = page_boxes[new_start_i][last_box_j] -- last highlighted box of the line
                pboxes[1].w = last_box.x1 - pboxes[1].x
            end
            local removed_word = page_boxes[start_i][start_j].word
            if removed_word then
                highlight.text = highlight.text:sub(#removed_word + 2) -- remove first word and space after it
            end
        else -- move highlight to the left
            local new_box
            if start_j == 1 then -- first box of the line
                if start_i == 1 then return end -- first line of the page, don't move to the previous page
                new_start_i = start_i - 1
                new_start_j = #page_boxes[new_start_i]
                new_box = page_boxes[new_start_i][new_start_j]
                table.insert(pboxes, 1, { x = new_box.x0, y = new_box.y0, w = new_box.x1 - new_box.x0, h = new_box.y1 - new_box.y0 })
            else
                new_start_i = start_i
                new_start_j = start_j - 1
                new_box = page_boxes[new_start_i][new_start_j]
                pboxes[1].x = new_box.x0
                local last_box_j = new_start_i == new_end_i and new_end_j or #page_boxes[new_start_i]
                local last_box = page_boxes[new_start_i][last_box_j] -- last highlighted box of the line
                pboxes[1].w = last_box.x1 - pboxes[1].x
            end
            if new_box.word then
                highlight.text = new_box.word .. " " .. highlight.text
            end
        end
    else -- we move pos1
        new_start_i, new_start_j = start_i, start_j
        if direction == 1 then -- move highlight to the right
            local new_box
            if end_j == #page_boxes[end_i] then -- last box of the line
                if end_i == #page_boxes then return end -- last line of the page, don't move to the next page
                new_end_i = end_i + 1
                new_end_j = 1
                new_box = page_boxes[new_end_i][new_end_j]
                table.insert(pboxes, { x = new_box.x0, y = new_box.y0, w = new_box.x1 - new_box.x0, h = new_box.y1 - new_box.y0 })
            else
                new_end_i = end_i
                new_end_j = end_j + 1
                new_box = page_boxes[new_end_i][new_end_j]
                pboxes[#pboxes].w = new_box.x1 - pboxes[#pboxes].x
            end
            if new_box.word then
                highlight.text = highlight.text .. " " .. new_box.word
            end
        else -- move highlight to the left
            if start_i == end_i and start_j == end_j then return end -- don't move end before start
            if end_j == 1 then -- first box of the line
                new_end_i = end_i - 1
                new_end_j = #page_boxes[new_end_i]
                table.remove(pboxes)
            else
                new_end_i = end_i
                new_end_j = end_j - 1
                local last_box = page_boxes[new_end_i][new_end_j] -- last highlighted box of the line
                pboxes[#pboxes].w = last_box.x1 - pboxes[#pboxes].x
            end
            local removed_word = page_boxes[end_i][end_j].word
            if removed_word then
                highlight.text = highlight.text:sub(1, -(#removed_word + 2)) -- remove last word and space before it
            end
        end
    end
    start_box, end_box = page_boxes[new_start_i][new_start_j], page_boxes[new_end_i][new_end_j]
    if highlight.ext then -- multipage highlight
        if side == 0 then -- we move pos0
            highlight.pos0.x = (start_box.x0 + start_box.x1) / 2
            highlight.pos0.y = (start_box.y0 + start_box.y1) / 2
            highlight.ext[page].pos0.x = highlight.pos0.x
            highlight.ext[page].pos0.y = highlight.pos0.y
        else
            highlight.pos1.x = (end_box.x0 + end_box.x1) / 2
            highlight.pos1.y = (end_box.y0 + end_box.y1) / 2
            highlight.ext[page].pos1.x = highlight.pos1.x
            highlight.ext[page].pos1.y = highlight.pos1.y
        end
    else
        -- pos0 and pos1 may be not in order, reassign all
        highlight.pos0.x = (start_box.x0 + start_box.x1) / 2
        highlight.pos0.y = (start_box.y0 + start_box.y1) / 2
        highlight.pos1.x = (end_box.x0 + end_box.x1) / 2
        highlight.pos1.y = (end_box.y0 + end_box.y1) / 2
    end
    return true
end

function ReaderHighlight:showChooseHighlightDialog(highlights)
    if #highlights == 1 then
        self:showHighlightNoteOrDialog(highlights[1])
    else -- overlapped highlights
        local dialog
        local buttons = {}
        for i, index in ipairs(highlights) do
            local item = self.ui.annotation.annotations[index]
            buttons[i] = {{
                text = (item.note and self.ui.bookmark.display_prefix["note"]
                                   or self.ui.bookmark.display_prefix["highlight"]) .. item.text,
                avoid_text_truncation = false,
                menu_style = true,
                callback = function()
                    UIManager:close(dialog)
                    self:showHighlightNoteOrDialog(index)
                end,
            }}
        end
        dialog = ButtonDialog:new{
            buttons = buttons,
        }
        UIManager:show(dialog)
    end
    return true
end

function ReaderHighlight:showHighlightNoteOrDialog(index)
    local resolve = self:makeHighlightResolver(index)
    local anno = self.ui.annotation.annotations[index]
    local bookmark_note = anno.note
    if bookmark_note then
        local note_format = anno.note_format
        if not note_format then -- try simple heuristics
            local s = bookmark_note:gsub("^%s*", ""):sub(1, 1)
            if s == "<" then
                note_format = "html"
            elseif s == "#" or s == "*" or s == "[" then
                note_format = "md"
            end
        end
        local ratio_w, ratio_h
        if note_format then
            ratio_w, ratio_h = 0.9, 0.8
        else
            ratio_w, ratio_h = 0.8, 0.4
        end
        local textviewer
        textviewer = TextViewer:new{
            title = _("Note"),
            show_menu = note_format ~= nil,
            text = bookmark_note,
            text_format = note_format,
            width = math.floor(math.min(self.screen_w, self.screen_h) * ratio_w),
            height = math.floor(math.max(self.screen_w, self.screen_h) * ratio_h),
            anchor = function()
                return self:_getDialogAnchor(textviewer, resolve())
            end,
            buttons_table = {
                {
                    {
                        text = _("Delete note"),
                        callback = function()
                            UIManager:close(textviewer)
                            local current = resolve()
                            if not current then return end
                            local annotation = self.ui.annotation.annotations[current]
                            if self:writePdfAnnotation("content", annotation, "") == false then return end
                            annotation = self.ui.annotation.annotations[current]
                            annotation.note = nil
                            self.ui:handleEvent(Event:new("AnnotationsModified",
                                    { annotation, nb_highlights_added = 1, nb_notes_added = -1 }))
                            if self.view.highlight.note_mark then -- refresh note marker
                                UIManager:setDirty(self.dialog, "ui")
                            end
                        end,
                    },
                    {
                        text = _("Edit note"),
                        callback = function()
                            UIManager:close(textviewer)
                            local current = resolve()
                            if current then self:editNote(current) end
                        end,
                    },
                },
                {
                    {
                        text = _("Delete highlight"),
                        callback = function()
                            UIManager:close(textviewer)
                            local current = resolve()
                            if current then self:deleteHighlight(current) end
                        end,
                    },
                    {
                        text = _("Highlight menu"),
                        callback = function()
                            UIManager:close(textviewer)
                            local current = resolve()
                            if current then self:showHighlightDialog(current) end
                        end,
                    },
                },
            },
        }
        UIManager:show(textviewer)
    else
        local current = resolve()
        if current then self:showHighlightDialog(current) end
    end
end

-- A dialog may outlive a sort, import, deletion or a transaction table swap.
-- Bind it to one item; never reuse its old array offset for a different item.
function ReaderHighlight:makeHighlightResolver(index)
    local selected = self.ui.annotation.annotations[index]
    local function resolve()
        if not selected then return end
        for i, item in ipairs(self.ui.annotation.annotations) do
            if item == selected then return i end
        end
        local fingerprint = require("document/pdfannotations").fingerprint
        local key, found = fingerprint(selected), nil
        for i, item in ipairs(self.ui.annotation.annotations) do
            if fingerprint(item) == key then
                if found then return end -- ambiguous copies are never guessed
                found = i
            end
        end
        if found then selected = self.ui.annotation.annotations[found] end
        return found
    end
    local function refresh(new_index)
        selected = new_index and self.ui.annotation.annotations[new_index] or nil
    end
    return resolve, refresh
end

function ReaderHighlight:showFullHighlightDialog(index)
    local resolve, refresh = self:makeHighlightResolver(index)
    local item = self.ui.annotation.annotations[index]
    local change_boundaries_enabled = not item.text_edited
    local start_prev, start_next, end_prev, end_next = "◁▒▒", "▷☓▒", "▒☓◁", "▒▒▷"
    if BD.mirroredUILayout() then
        -- BiDi will mirror the arrows, and this just works
        start_prev, start_next = start_next, start_prev
        end_prev, end_next = end_next, end_prev
    end
    local move_by_char = false
    local edit_highlight_dialog
    local buttons = {
        {
            {
                text = "\u{F48E}", -- Trash can (icon to prevent confusion of Delete/Details buttons)
                callback = function()
                    self:deleteHighlight(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = C_("Highlight", "Style"),
                callback = function()
                    self:editHighlightStyle(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = C_("Highlight", "Color"),
                enabled = item.drawer ~= "invert",
                callback = function()
                    self:editHighlightColor(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = _("Note"),
                callback = function()
                    self:editNote(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = _("Details"),
                callback = function()
                    self.ui.bookmark:showBookmarkDetails(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = "…",
                callback = function()
                    self.selected_text = util.tableDeepCopy(item)
                    self:onShowHighlightMenu(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
        },
        {
            {
                text = start_prev,
                enabled = change_boundaries_enabled,
                callback = function()
                    return self:updateHighlight(index, 0, -1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    return self:updateHighlight(index, 0, -1, true)
                end,
            },
            {
                text = start_next,
                enabled = change_boundaries_enabled,
                callback = function()
                    return self:updateHighlight(index, 0, 1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    return self:updateHighlight(index, 0, 1, true)
                end,
            },
            {
                text = end_prev,
                enabled = change_boundaries_enabled,
                callback = function()
                    return self:updateHighlight(index, 1, -1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    return self:updateHighlight(index, 1, -1, true)
                end,
            },
            {
                text = end_next,
                enabled = change_boundaries_enabled,
                callback = function()
                    return self:updateHighlight(index, 1, 1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    return self:updateHighlight(index, 1, 1, true)
                end,
            },
        },
    }
    for _, row in ipairs(buttons) do
        for _, button in ipairs(row) do
            for _, key in ipairs({"callback", "hold_callback"}) do
                local callback = button[key]
                if callback then
                    button[key] = function(...)
                        local current = resolve()
                        if not current then UIManager:close(edit_highlight_dialog); return end
                        index = current
                        item = self.ui.annotation.annotations[index]
                        local changed, updated_index = callback(...)
                        -- A boundary crossing may also reorder the annotation.
                        refresh(changed == true and type(updated_index) == "number" and updated_index or index)
                    end
                end
            end
        end
    end
    edit_highlight_dialog = ButtonDialog:new{
        name = "edit_highlight_dialog", -- for unit tests
        buttons = buttons,
        anchor = function()
            return self:_getDialogAnchor(edit_highlight_dialog, resolve())
        end,
    }
    UIManager:show(edit_highlight_dialog)
end

function ReaderHighlight:addToHighlightDialog(idx, fn_button)
    -- fn_button is a function that takes the ReaderHighlight instance
    -- as argument, and returns a table describing the button to be added.
    self._highlight_buttons[idx] = fn_button
end

function ReaderHighlight:removeFromHighlightDialog(idx)
    local button = self._highlight_buttons[idx]
    self._highlight_buttons[idx] = nil
    return button
end

function ReaderHighlight:onShowHighlightMenu(index)
    if not self.selected_text then
        return
    end

    local highlight_buttons = {{}}

    local columns = 2
    for idx, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
        local button = fn_button(self, index)
        if not button.show_in_highlight_dialog_func or button.show_in_highlight_dialog_func() then
            if #highlight_buttons[#highlight_buttons] >= columns then
                table.insert(highlight_buttons, {})
            end
            table.insert(highlight_buttons[#highlight_buttons], button)
            logger.dbg("ReaderHighlight", idx..": line "..#highlight_buttons..", col "..#highlight_buttons[#highlight_buttons])
        end
    end

    self.highlight_dialog = ButtonDialog:new{
        buttons = highlight_buttons,
        anchor = function()
            return self:_getDialogAnchor(self.highlight_dialog, index)
        end,
        tap_close_callback = function()
            if self.hold_pos then
                self:clear()
            end
        end,
    }
    -- NOTE: Disable merging for this update,
    --       or the buggy Sage kernel may alpha-blend it into the page (with a bogus alpha value, to boot)...
    UIManager:show(self.highlight_dialog, "[ui]")
end

function ReaderHighlight:_getDialogAnchor(dialog, index)
    local position = G_reader_settings:readSetting("highlight_dialog_position", "center")
    if position == "center" then return end
    local padding = Size.padding.small -- vertical padding, do not stick to the highlight box or to the screen edge
    if position == "top" then
        return { y = padding }
    elseif position == "bottom" then
        return { y = self.screen_h - padding }
    else -- "gesture"
        local boxes = index and self:getHighlightVisibleBoxes(index) or (self.selected_text.sboxes or self.selected_text.pboxes)
        if boxes == nil then return end -- fallback to "center"
        local box0, box1 = boxes[1], boxes[#boxes]
        if box0.y > box1.y then
            box0, box1 = box1, box0
        end
        if self.ui.paging then
            local page = index and self.ui.annotation.annotations[index].pos0.page or self.selected_text.pos0.page
            box0 = self.view:pageToScreenTransform(page, box0)
            box1 = self.view:pageToScreenTransform(page, box1)
            if box0 == nil or box1 == nil then return end
        end
        local y0 = box0.y
        local y1 = box1.y + box1.h
        local dialog_box_h = dialog:getContentSize().h + 2 * padding
        if y1 + dialog_box_h <= self.screen_h then -- below highlight, preferable
            return { y = y1 + padding }, true -- pop down
        elseif dialog_box_h <= y0 then -- above highlight
            return { y = y0 - padding }
        end
    end
end

function ReaderHighlight:_resetHoldTimer(clear)
    if not self.long_hold_reached_action then
        self.long_hold_reached_action = function()
            self.long_hold_reached = true
            -- Have ReaderView redraw and refresh ReaderFlipping and our state icon, avoiding flashes
            UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
        end
    end
    -- Unschedule if already set
    UIManager:unschedule(self.long_hold_reached_action)

    if not clear then
        -- We don't need to handle long-hold and show its icon in some configurations
        -- where it would not change the behaviour from the normal-hold one (but we still
        -- need to go through the checks below to clear any long_hold_reached set when in
        -- the word->multiwords selection transition).
        -- (It feels we don't need to care about default_highlight_action="nothing" here.)
        local handle_long_hold = true
        if self.is_word_selection then
            -- Single word normal-hold defaults to dict lookup, and long-hold defaults to "ask".
            -- If normal-hold is set to use the highlight action, and this action is still "ask",
            -- no need to handle long-hold.
            if G_reader_settings:isTrue("highlight_action_on_single_word") and
                   G_reader_settings:readSetting("default_highlight_action", "ask") == "ask" then
                handle_long_hold = false
            end
        else
            -- Multi words selection uses default_highlight_action, and no need for long-hold
            -- if it is already "ask".
            if G_reader_settings:readSetting("default_highlight_action", "ask") == "ask" then
                handle_long_hold = false
            end
        end
        if handle_long_hold then
            UIManager:scheduleIn(G_reader_settings:readSetting("highlight_long_hold_threshold_s")
                or GestureDetector.LONG_HOLD_INTERVAL_S, self.long_hold_reached_action)
        end
    end
    -- Unset flag and icon
    if self.long_hold_reached then
        self.long_hold_reached = false
        -- Have ReaderView redraw and refresh ReaderFlipping with our state icon removed
        UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
    end
end

function ReaderHighlight:onTogglePanelZoomSetting(arg, ges)
    if self.ui.rolling then return end
    self.panel_zoom_enabled = not self.panel_zoom_enabled
end

function ReaderHighlight:onToggleFallbackTextSelection(arg, ges)
    if self.ui.rolling then return end
    self.panel_zoom_fallback_to_text_selection = not self.panel_zoom_fallback_to_text_selection
end

function ReaderHighlight:onPanelZoom(arg, ges)
    self:clear()
    local hold_pos = self.view:screenToPageTransform(ges.pos)
    if not hold_pos then return false end -- outside page boundary
    local rect = self.ui.document:getPanelFromPage(hold_pos.page, hold_pos)
    if not rect then return false end -- panel not found, return
    local image, rotate = self.ui.document:drawPagePart(hold_pos.page, rect, 0)

    if image then
        local ImageViewer = require("ui/widget/imageviewer")
        local imgviewer = ImageViewer:new{
            image = image,
            image_disposable = false, -- It's a TileCache item
            with_title_bar = false,
            fullscreen = true,
            rotated = rotate,
        }
        UIManager:show(imgviewer)
        return true
    end
    return false
end

function ReaderHighlight:onHold(arg, ges)
    if self.ui.paging and self.panel_zoom_enabled then
        local res = self:onPanelZoom(arg, ges)
        if res or not self.panel_zoom_fallback_to_text_selection then
            return res
        end
    end

    self:clear() -- clear previous highlight (delayed clear may not have done it yet)
    self.hold_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("hold position in page", self.hold_pos)
    if not self.hold_pos then
        logger.dbg("not inside page area")
        return false
    end

    self.allow_hold_pan_corner_scroll = false -- reset this, don't allow that yet

    -- check if we were holding on an image
    -- we provide want_frames=true, so we get a list of images for
    -- animated GIFs (supported by ImageViewer)
    -- We provide accept_cre_scalable_image=true to get, if the image is a SVG image,
    -- a function that ImageViewer can use to get a perfect bb at any scale factor.
    local image = self.ui.document:getImageFromPosition(self.hold_pos, true, true)
    if image then
        logger.dbg("hold on image")
        self.hold_pos = nil
        local ImageViewer = require("ui/widget/imageviewer")
        UIManager:show(ImageViewer:new{
            image = image,
            with_title_bar = false, -- more room for image
            fullscreen = true,
        })
        self.ui.keyselection:stopHighlightIndicator()
        return true
    end

    -- otherwise, we must be holding on text
    if self.view.highlight.disabled then -- Long-press action "Do nothing" checked
        self.hold_pos = nil
        return false
    end
    local ok, word = pcall(self.ui.document.getWordFromPosition, self.ui.document, self.hold_pos)
    if ok and word then
        logger.dbg("selected word:", word)
        -- Convert "word selection" table to "text selection" table because we
        -- use text selections throughout readerhighlight in order to allow the
        -- highlight to be corrected by language-specific plugins more easily.
        self.is_word_selection = true
        local pos = word.pos
        self.selected_text = {
            text = word.word or "",
            pos0 = word.pos0 or {
                page     = pos.page,
                rotation = pos.rotation,
                x        = pos.x,
                y        = pos.y,
                zoom     = pos.zoom,
            },
            pos1 = word.pos1 or {
                page     = pos.page,
                rotation = pos.rotation,
                x        = pos.x,
                y        = pos.y,
                zoom     = pos.zoom,
            },
            sboxes = word.sbox and { word.sbox },
            pboxes = word.pbox and { word.pbox },
        }
        local link = self.ui.link:getLinkFromGes(ges)
        self.selected_link = nil
        if link then
            logger.dbg("link:", link)
            self.selected_link = link
        end

        if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
            -- If this is a language where pan-less word selection needs some
            -- extra work above and beyond what the document engine gives us
            -- from getWordFromPosition, call the relevant language-specific
            -- plugin.
            local new_selected_text = self.ui.languagesupport:improveWordSelection(self.selected_text)
            if new_selected_text then
                self.selected_text = new_selected_text
            end
        end

        if self.ui.paging then
            self.view.highlight.temp[self.hold_pos.page] = self.selected_text.sboxes
            -- Unfortunately, getWordFromPosition() may not return good coordinates,
            -- so refresh the whole page
            UIManager:setDirty(self.dialog, "ui")
        else
            -- With crengine, getWordFromPosition() does return good coordinates.
            UIManager:setDirty(self.dialog, "ui", Geom.boundingBox(self.selected_text.sboxes))
        end
        self:_resetHoldTimer()
        if word.pos0 then
            -- Remember original highlight start position, so we can show
            -- a marker when back from across-pages text selection, which
            -- is handled in onHoldPan()
            self.selected_text_start_xpointer = word.pos0
        end
        return true
    end
    if self.ui.rolling then
        -- It has happened it failed because the text range was detected on the
        -- previous page and highlighted by crengine, but no word was returned
        -- (because the boxes were not on the current page).
        -- Be sure we clear any such selection
        self.ui.document:clearSelection()
    end
    -- Be sure we don't get stuck in a hold state
    self.hold_pos = nil
    return false
end

function ReaderHighlight:onHoldPan(_, ges)
    if self.view.highlight.disabled then return false end -- Long-press action "Do nothing" checked
    if self.hold_pos == nil then
        logger.dbg("no previous hold position")
        self:_resetHoldTimer(true)
        return true
    end
    local page_area = self.view:getScreenPageArea(self.hold_pos.page)
    if ges.pos:notIntersectWith(page_area) then
        logger.dbg("not inside page area", ges, page_area)
        self:_resetHoldTimer()
        return true
    end

    self.holdpan_pos = self.view:screenToPageTransform(ges.pos)
    logger.dbg("holdpan position in page", self.holdpan_pos)

    if self.ui.rolling and self.allow_corner_scroll and self.selected_text_start_xpointer then
        -- With CreDocuments, allow text selection across multiple pages
        -- by (temporarily) switching to scroll mode when panning to the
        -- top left or bottom right corners.
        local mirrored_reading = BD.mirroredUILayout()
        if self.view.inverse_reading_order then
            mirrored_reading = not mirrored_reading
        end
        local is_in_prev_page_corner, is_in_next_page_corner
        if mirrored_reading then
            -- Note: this might not be really usable, as crengine native selection
            -- is not adapted to RTL text
            -- top right corner
            is_in_prev_page_corner = self.holdpan_pos.y < 1/8*self.screen_h
                                      and self.holdpan_pos.x > 7/8*self.screen_w
            -- bottom left corner
            is_in_next_page_corner = self.holdpan_pos.y > 7/8*self.screen_h
                                          and self.holdpan_pos.x < 1/8*self.screen_w
        else -- default in LTR UI with no inverse_reading_order
            -- top left corner
            is_in_prev_page_corner = self.holdpan_pos.y < 1/8*self.screen_h
                                      and self.holdpan_pos.x < 1/8*self.screen_w
            -- bottom right corner
            is_in_next_page_corner = self.holdpan_pos.y > 7/8*self.screen_h
                                      and self.holdpan_pos.x > 7/8*self.screen_w
        end
        if not self.allow_hold_pan_corner_scroll then
            if not is_in_prev_page_corner and not is_in_next_page_corner then
                -- We expect the user to come from a non-corner zone into a corner
                -- to enable this; this allows normal highlighting without scrolling
                -- if the selection is started in the corner: the user will have to
                -- move out from and go back in to trigger a scroll.
                self.allow_hold_pan_corner_scroll = true
            end
        elseif is_in_prev_page_corner or is_in_next_page_corner then
            self:_resetHoldTimer()
            if self.was_in_some_corner then
                -- Do nothing, wait for the user to move his finger out of that corner
                return true
            end
            self.was_in_some_corner = true
            if self.ui.document:getVisiblePageCount() == 1 then -- single page mode
                -- We'll adjust hold_pos.y after the mode switch and the scroll
                -- so it's accurate in the new screen coordinates
                local orig_y = self.ui.document:getScreenPositionFromXPointer(self.selected_text_start_xpointer)
                if self.view.view_mode ~= "scroll" then
                    -- Switch from page mode to scroll mode
                    local restore_page_mode_xpointer = self.ui.document:getXPointer() -- top of current page
                    self.restore_page_mode_func = function()
                        self.ui:handleEvent(Event:new("SetViewMode", "page"))
                        self.ui.rolling:onGotoXPointer(restore_page_mode_xpointer, self.selected_text_start_xpointer)
                    end
                    self.ui:handleEvent(Event:new("SetViewMode", "scroll"))
                end
                -- (using rolling:onGotoViewRel(1/3) has some strange side effects)
                local scroll_distance = math.floor(self.screen_h * 1/3)
                local move_y = is_in_next_page_corner and scroll_distance or -scroll_distance
                self.ui.rolling:_gotoPos(self.ui.document:getCurrentPos() + move_y)
                local new_y = self.ui.document:getScreenPositionFromXPointer(self.selected_text_start_xpointer)
                self.hold_pos.y = self.hold_pos.y - orig_y + new_y
                UIManager:setDirty(self.dialog, "ui")
                return true
            else -- two pages mode
                -- We don't switch to scroll mode: we just turn 1 page to
                -- allow continuing the selection.
                -- Unlike in 1-page mode, we have a limitation here: we can't adjust
                -- the selection to further than current page and prev/next one.
                -- So don't handle another corner if we already handled one:
                -- Note that this feature won't work well with the RTL UI or
                -- if inverse_reading_order as crengine currently always displays
                -- the first page on the left and the second on the right in
                -- dual page mode.
                if self.restore_page_mode_func then
                    return true
                end
                -- Also, we are not able to move hold_pos.x out of screen,
                -- so if we started on the right page, ignore top left corner,
                -- and if we started on the left page, ignore bottom right corner.
                local screen_half_width = math.floor(self.screen_w * 0.5)
                if self.hold_pos.x >= screen_half_width and is_in_prev_page_corner then
                    return true
                elseif self.hold_pos.x <= screen_half_width and is_in_next_page_corner then
                    return true
                end
                -- To be able to browse half-page when 2 visible pages as 1 page number,
                -- we must work with internal page numbers
                local cur_page = self.ui.document:getCurrentPage(true)
                local restore_page_mode_xpointer = self.ui.document:getXPointer() -- top of current page
                self.ui.document.no_page_sync = true -- avoid CreDocument:drawCurrentViewByPage() to resync page
                self.restore_page_mode_func = function()
                    self.ui.document.no_page_sync = nil
                    self.ui.rolling:onGotoXPointer(restore_page_mode_xpointer, self.selected_text_start_xpointer)
                end
                if is_in_next_page_corner then -- bottom right corner in LTR UI
                    self.ui.rolling:_gotoPage(cur_page + 1, true, true) -- no odd left page enforcement
                    self.hold_pos.x = self.hold_pos.x - screen_half_width
                else -- top left corner in RTL UI
                    self.ui.rolling:_gotoPage(cur_page - 1, true, true) -- no odd left page enforcement
                    self.hold_pos.x = self.hold_pos.x + screen_half_width
                end
                UIManager:setDirty(self.dialog, "ui")
                return true
            end
        else
            self.was_in_some_corner = nil
        end
    end

    local old_text = self.selected_text and self.selected_text.text
    self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.holdpan_pos)
    self.is_word_selection = false

    if self.selected_text and self.selected_text.pos0 then
        if not self.selected_text_start_xpointer then
            -- This should have been set in onHold(), where we would get
            -- a precise pos0 on the first word selected.
            -- Do it here too in case onHold() missed it, but it could be
            -- less precise (getTextFromPositions() does order pos0 and pos1,
            -- so it's not certain pos0 is where we started from; we get
            -- the ones from the first pan, and if it is not small enough
            -- and spans quite some height, the marker could point away
            -- from the start position)
            self.selected_text_start_xpointer = self.selected_text.pos0
        end
    end

    if self.selected_text and old_text and old_text == self.selected_text.text then
        -- no modification
        return
    end
    self:_resetHoldTimer() -- selection updated
    logger.dbg("selected text:", self.selected_text)
    if self.ui.paging and self.selected_text then
        self.view.highlight.temp[self.hold_pos.page] = self.selected_text.sboxes
    end
    -- Ensure indicator overlay does not restore stale background over updated highlights.
    if self.ui.keyselection:isActive() then
        self.ui.keyselection:clearOverlay()
    end
    UIManager:setDirty(self.dialog, "ui")
end

local info_message_ocr_text = _([[
No OCR results or no language data.

KOReader has a built-in OCR engine for recognizing words in scanned PDF and DjVu documents. In order to use OCR in scanned pages, you need to install tesseract trained data for your document language.

You can download language data files for Tesseract version 5.3.4 from https://tesseract-ocr.github.io/tessdoc/Data-Files

Copy the language data files (e.g., eng.traineddata for English and spa.traineddata for Spanish) into koreader/data/tessdata]])

function ReaderHighlight:lookupDictWord()
    -- convert sboxes to word boxes
    local word_boxes = {}
    for i, sbox in ipairs(self.selected_text.sboxes) do
        word_boxes[i] = self.view:pageToScreenTransform(self.hold_pos.page, sbox)
    end
    -- if we extracted text directly
    if #self.selected_text.text > 0 then
        self.ui.dictionary:onLookupWord(self.selected_text.text, false, word_boxes, self, self.selected_link)
    -- or we will do OCR
    elseif self.selected_text.sboxes then
        local text = self.ui.document:getOCRText(self.hold_pos.page, self.selected_text.sboxes)
        if not text then
            -- getOCRText is not implemented in some document backends, but
            -- getOCRWord is implemented everywhere. As such, fall back to
            -- getOCRWord.
            text = ""
            for _, sbox in ipairs(self.selected_text.sboxes) do
                local word = self.ui.document:getOCRWord(self.hold_pos.page, { sbox = sbox })
                logger.dbg("OCRed word:", word)
                --- @fixme This might produce incorrect results on RTL text.
                text = text .. (word or "")
            end
        end
        logger.dbg("OCRed text:", text)
        if text and text ~= "" then
            self.ui.dictionary:onLookupWord(text, false, word_boxes, self, self.selected_link)
        else
            UIManager:show(InfoMessage:new{
                text = info_message_ocr_text,
            })
            UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"),function()
                self:clear()
            end)
        end
    end
end

function ReaderHighlight:getSelectedWordContext(nb_words)
    if not self.selected_text then return end
    local ok, prev_context, next_context = pcall(self.ui.document.getSelectedWordContext, self.ui.document,
                                                 self.selected_text.text, nb_words, self.selected_text.pos0, self.selected_text.pos1, true)
    if ok then
        return prev_context, next_context
    end
end

function ReaderHighlight:viewSelectionHTML(debug_view, no_css_files_buttons)
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        local ViewHtml = require("ui/viewhtml")
        ViewHtml:viewSelectionHTML(self.ui.document, self.selected_text)
    end
end

function ReaderHighlight:translate(index)
    if self.ui.rolling then
        -- Extend the selected text to include any punctuation at start or end,
        -- which may give a better translation with the added context.
        local extended_text = self.ui.document:extendXPointersToSentenceSegment(self.selected_text.pos0, self.selected_text.pos1)
        if extended_text then
            self.selected_text = extended_text
        end
    end
    if #self.selected_text.text > 0 then
        self:onTranslateText(self.selected_text.text, index)
    -- or we will do OCR
    elseif self.hold_pos then
        local text = self.ui.document:getOCRText(self.hold_pos.page, self.selected_text)
        logger.dbg("OCRed text:", text)
        if text and text ~= "" then
            self:onTranslateText(text)
        else
            UIManager:show(InfoMessage:new{
                text = info_message_ocr_text,
            })
            UIManager:scheduleIn(G_defaults:readSetting("DELAY_CLEAR_HIGHLIGHT_S"),function()
                self:clear()
            end)
        end
    end
end

function ReaderHighlight:onTranslateText(text, index)
    Translator:showTranslation(text, true, nil, nil, true, index)
end

function ReaderHighlight:onTranslateCurrentPage()
    local x0, y0, x1, y1, page, is_reflow
    if self.ui.rolling then
        x0 = 0
        y0 = 0
        x1 = self.screen_w
        y1 = self.screen_h
    else
        page = self.ui:getCurrentPage()
        is_reflow = self.ui.document.configurable.text_wrap
        self.ui.document.configurable.text_wrap = 0
        local page_boxes = self.ui.document:getTextBoxes(page)
        if page_boxes and page_boxes[1][1].word then
            x0 = page_boxes[1][1].x0
            y0 = page_boxes[1][1].y0
            x1 = page_boxes[#page_boxes][#page_boxes[#page_boxes]].x1
            y1 = page_boxes[#page_boxes][#page_boxes[#page_boxes]].y1
        end
    end
    local res = x0 and self.ui.document:getTextFromPositions({x = x0, y = y0, page = page}, {x = x1, y = y1}, true)
    if self.ui.paging then
        self.ui.document.configurable.text_wrap = is_reflow
    end
    if res and res.text then
        Translator:showTranslation(res.text, false, self.ui.doc_props.language)
    end
end

function ReaderHighlight:onHoldRelease()
    if self.clear_id then
        -- Something has requested a clear id and is about to clear
        -- the highlight: it may be a onHoldClose() that handled
        -- "hold" and was closed, and can't handle "hold_release":
        -- ignore this "hold_release" event.
        return true
    end

    local long_final_hold = self.long_hold_reached
    self:_resetHoldTimer(true) -- clear state

    local default_highlight_action = G_reader_settings:readSetting("default_highlight_action", "ask")

    if self.select_mode then -- extended highlighting, ending fragment
        if self.selected_text then
            self.select_mode = false
            if self:extendSelection() == false then return true end
            if self.selected_text.is_extended then
                self:saveHighlight(true)
                self:clear()
            elseif default_highlight_action == "select" then
                self:showHighlightPrompt()
            else
                self:onShowHighlightMenu()
            end
        end
        return true
    end

    if self.is_word_selection then -- single-word selection
        if long_final_hold or G_reader_settings:isTrue("highlight_action_on_single_word") then
            self.is_word_selection = false
        end
    end

    if self.selected_text then
        if self.is_word_selection then
            self:lookupDictWord()
        else
            if long_final_hold or default_highlight_action == "ask" then
                -- bypass default action and show popup if long final hold
                self:onShowHighlightMenu()
            elseif default_highlight_action == "highlight" then
                self:showHighlightPrompt()
            elseif default_highlight_action == "select" then
                self:startSelection()
                self:onClose()
            elseif default_highlight_action == "note" then
                self:addNote()
                self:onClose()
            elseif default_highlight_action == "ai_translate" then
                self:translateWithAssistant()
            elseif default_highlight_action == "translate" then
                self:translate()
            elseif default_highlight_action == "wikipedia" then
                self:lookupWikipedia()
                self:onClose()
            elseif default_highlight_action == "dictionary" then
                self:lookupDict()
                self:onClose(true) -- keep selected text
            elseif default_highlight_action == "search" then
                self:onHighlightSearch()
                -- No self:onClose() to not remove the selected text
                -- which will have been the first search result
            end
        end
    end
    return true
end

function ReaderHighlight:getHighlightActions() -- for Dispatcher
    local action_nums, action_texts = {}, {}
    for i, v in ipairs(long_press_action) do
        table.insert(action_nums, i)
        table.insert(action_texts, v[1])
    end
    return action_nums, action_texts
end

function ReaderHighlight:onSetHighlightAction(action_num, no_notification)
    local v = long_press_action[action_num]
    if not v then return false end
    G_reader_settings:saveSetting("default_highlight_action", v[2])
    self.view.highlight.disabled = v[2] == "nothing"
    if not no_notification then -- fired with a gesture
        UIManager:show(Notification:new{
            text = T(_("Default highlight action changed to '%1'."), v[1]),
        })
    end
    return true
end

function ReaderHighlight:onCycleHighlightAction()
    local current_action = G_reader_settings:readSetting("default_highlight_action", "ask")
    local next_action_num = 1 -- unknown legacy/custom actions cycle safely to Ask
    for i, v in ipairs(long_press_action) do
        if v[2] == current_action then
            next_action_num = i + 1
            break
        end
    end
    if next_action_num > #long_press_action then
        next_action_num = 1
    end
    self:onSetHighlightAction(next_action_num)
    return true
end

function ReaderHighlight.getHighlightStyles()
    return highlight_style
end

function ReaderHighlight:getHighlightStyleString(style) -- for bookmark list
    for _, v in ipairs(highlight_style) do
        if v[2] == style then
            return v[1]
        end
    end
end

function ReaderHighlight:onCycleHighlightStyle()
    local current_style = self.view.highlight.saved_drawer
    local next_style_num
    for i, v in ipairs(highlight_style) do
        if v[2] == current_style then
            next_style_num = i + 1
            break
        end
    end
    if next_style_num > #highlight_style then
        next_style_num = 1
    end
    self.view.highlight.saved_drawer = highlight_style[next_style_num][2]
    UIManager:show(Notification:new{
        text = T(_("Default highlight style changed to '%1'."), highlight_style[next_style_num][1]),
    })
    return true
end

function ReaderHighlight:highlightWordAtCoordinates(x, y)
    if not self.ui.rolling then return end
    if not (x and y) then return end
    self.hold_pos = { x = x, y = y }
    local word = self.ui.document:getWordFromPosition(self.hold_pos)
    if not (word and word.sbox) then
        return false
    end
    self.is_word_selection = true
    local pos = word.pos
    self.selected_text = {
        text = word.word or "",
        pos0 = word.pos0 or pos,
        pos1 = word.pos1 or pos,
        sboxes = { word.sbox },
        pboxes = word.pbox and { word.pbox },
    }
    UIManager:setDirty(self.dialog, "ui", Geom.boundingBox(self.selected_text.sboxes))
    return true
end

function ReaderHighlight:highlightFromHoldPos()
    if self.hold_pos then
        if not self.selected_text then
            self.selected_text = self.ui.document:getTextFromPositions(self.hold_pos, self.hold_pos)
            if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
                -- Match language-specific expansion you'd get from self:onHold().
                local new_selected_text = self.ui.languagesupport:improveWordSelection(self.selected_text)
                if new_selected_text then
                    self.selected_text = new_selected_text
                end
            end
            logger.dbg("selected text:", self.selected_text)
        end
    end
end

function ReaderHighlight:applyCurrentHighlightStyleAndColor()
    if not self:checkAnnotationEditingAllowed() then return 0 end
    local count = 0
    for index = 1, #self.ui.annotation.annotations do
        local item = self.ui.annotation.annotations[index]
        if item.drawer then
            if item.koreaderx_pdf_source then
                local candidate = util.tableDeepCopy(item)
                candidate.drawer, candidate.color = self.view.highlight.saved_drawer, self.view.highlight.saved_color
                if not self:commitImportedChange(index, candidate, "appearance") then break end
            else
                local candidate = util.tableDeepCopy(item)
                candidate.drawer, candidate.color = self.view.highlight.saved_drawer, self.view.highlight.saved_color
                if not self:commitOrdinaryChange(index, candidate) then break end
            end
            count = count + 1
        end
    end
    return count
end

function ReaderHighlight:checkAnnotationEditingAllowed()
    if self.document.is_pdf and not self.ui.doc_settings.koreaderx_transaction_blocked then
        local ok, err = pcall(require("document/pdfannotationtransaction").assertMetadataUnchanged, self.ui.doc_settings)
        if not ok then logger.warn("KOReaderX annotation metadata conflict:", err) end
    end
    if not self.ui.doc_settings.koreaderx_transaction_blocked then return true end
    UIManager:show(InfoMessage:new{ text = _("Annotation editing is disabled until the unfinished PDF transaction has been recovered. Close the book and preserve its PDF, sidecar and transaction backups.") })
    return false
end

function ReaderHighlight:saveHighlight(extend_to_sentence)
    if not self:checkAnnotationEditingAllowed() then return false end
    if self.selected_text and self.selected_text._koreaderx_owned_extend_index then
        local candidate = util.tableDeepCopy(self.selected_text)
        local index = candidate._koreaderx_owned_extend_index
        candidate._koreaderx_owned_extend_index, candidate.is_extended, candidate.is_tmp = nil, nil, nil
        local ok, updated_index = self:commitOrdinaryChange(index, candidate)
        if ok then return updated_index end
        return
    end
    if self.selected_text and self.selected_text._koreaderx_extend_index then
        local candidate = util.tableDeepCopy(self.selected_text)
        local index = candidate._koreaderx_extend_index
        candidate._koreaderx_extend_index, candidate.is_extended = nil, nil
        local committed, updated_index = self:commitImportedChange(index, candidate, "geometry")
        if committed then return updated_index end
        return
    end
    logger.dbg("save highlight")
    if self.hold_pos and not self.selected_text then
        self:highlightFromHoldPos()
    end
    if self.selected_text and self.selected_text.pos0 and self.selected_text.pos1 then
        local pg_or_xp
        if self.ui.rolling then
            if extend_to_sentence then
                local extended_text = self.ui.document:extendXPointersToSentenceSegment(self.selected_text.pos0, self.selected_text.pos1)
                if extended_text then
                    self.selected_text = extended_text
                end
            end
            pg_or_xp = self.selected_text.pos0
        else
            pg_or_xp = self.selected_text.pos0.page
        end
        local item = {
            page = self.ui.paging and self.selected_text.pos0.page or self.selected_text.pos0,
            pos0 = self.selected_text.pos0,
            pos1 = self.selected_text.pos1,
            text = util.cleanupSelectedText(self.selected_text.text),
            datetime = self.selected_text.datetime,
            drawer = self.selected_text.drawer or self.view.highlight.saved_drawer,
            color = self.selected_text.color or self.view.highlight.saved_color,
            note = self.selected_text.note,
            chapter = self.ui.toc:getTocTitleByPage(pg_or_xp),
        }
        if self.ui.paging then
            item.pboxes = self.selected_text.pboxes
            item.ext = self.selected_text.ext
            if self.document.is_pdf then item.koreaderx_pdf_owned = { version = 1, parts = {} } end
            if self:writePdfAnnotation("save", item) == false then return false end
        end
        local index = self.ui.annotation:addItem(item)
        self.view.footer:maybeUpdateFooter()
        self.ui:handleEvent(Event:new("AnnotationsModified",
            { item, nb_highlights_added = 1, index_modified = index, modify_datetime = self.selected_text.is_extended }))
        return index
    end
end

-- Preserve pending native ownership independently from imported annotations.
-- A complete raw snapshot plus object identity is required for ordinary edits.
function ReaderHighlight:writePdfAnnotation(action, item, content, previous)
    if not self:checkAnnotationEditingAllowed() then return false end
    if item.koreaderx_pdf_source then
        if action == "content" then
            local index = self.ui.annotation:getItemIndex(item)
            if not index then return false end
            local candidate = util.tableDeepCopy(item)
            candidate.note = content ~= "" and content or nil
            return self:commitImportedChange(index, candidate, "note")
        end
        return false
    end
    if not (self.document.is_pdf and self.highlight_write_into_pdf and item.drawer) then return true end
    local original = previous or item
    local prior = util.tableDeepCopy(original.koreaderx_pdf_owned or { version = 1, parts = {} })
    local parts, adjusted = {}, {}
    local function fragment(source, page_number, native_only)
        local part = not native_only and source.ext and self:getSavedExtendedHighlightPage(source, page_number) or util.tableDeepCopy(source)
        part.koreaderx_pdf_owned = { version = 1, parts = {} }
        for _, native in ipairs(source.koreaderx_pdf_owned and source.koreaderx_pdf_owned.parts or {}) do
            if native.page == page_number then table.insert(part.koreaderx_pdf_owned.parts, native) end
        end
        return part
    end
    local ok, err = pcall(function()
        self.document:checkPdfFileUnchanged()
        if action ~= "save" then self.document:validateOwnedAnnotation(original) end
        self.document:withOwnedAnnotationCandidate(function()
            if action == "delete" or action == "replace" then
                for _, native in ipairs(prior.parts) do
                    assert(self.document:deleteHighlight(native.page, fragment(original, native.page, true)) ~= false,
                        "Owned PDF annotation could not be deleted")
                end
            end
            if action == "save" or action == "replace" then
                for page = item.pos0.page, item.pos1.page do
                    local target = fragment(item, page)
                    local created = assert(self.document:saveHighlight(page, target))
                    if item.note then
                        target.koreaderx_pdf_owned.parts = { created }
                        created = assert(self.document:updateHighlightContents(page, target, item.note))
                    end
                    parts[#parts + 1] = created
                    adjusted[page] = target.pboxes
                end
            elseif action == "content" then
                for _, native in ipairs(prior.parts) do
                    local target = fragment(original, native.page, true)
                    local changed = self.document:updateHighlightContents(native.page, target, content)
                    assert(type(changed) == "table", "Owned PDF annotation note could not be updated")
                    parts[#parts + 1] = changed
                end
            end
        end)
    end)
    if not ok then
        logger.warn("KOReaderX owned annotation change failed:", err)
        UIManager:show(InfoMessage:new{ text = _("The PDF annotation change was not applied. Its ownership may be missing or changed; close/reopen and reconcile before retrying.") .. "\n" .. tostring(err) })
        return false
    end
    for page, boxes in pairs(adjusted) do
        if item.ext then item.ext[page].pboxes = boxes else item.pboxes = boxes end
    end
    item.koreaderx_pdf_owned = {
        version = 1, parts = parts,
        pending = prior.pending or { before_hash = self.document.koreaderx_open_hash, parts = prior.parts },
    }
    return true
end

function ReaderHighlight:commitOrdinaryChange(index, candidate, before)
    local live = self.ui.annotation.annotations[index]
    if candidate == live then candidate = util.tableDeepCopy(candidate) end
    local original = util.tableDeepCopy(before or live)
    if self:writePdfAnnotation("replace", candidate, nil, original) == false then return false end
    -- Keep ordinary item identity for open palettes, bookmark dialogs and EPUB
    -- callbacks, but only publish the detached candidate after native success.
    for key in pairs(live) do live[key] = nil end
    for key, value in pairs(candidate) do live[key] = value end
    candidate = live
    local updated_index = index
    if candidate.page ~= original.page and self.ui.paging then
        candidate.chapter = self.ui.toc:getTocTitleByPage(candidate.page)
        table.remove(self.ui.annotation.annotations, index)
        updated_index = self.ui.annotation:addItem(candidate)
    else
        self.ui.annotation.annotations[index] = candidate
    end
    if self.document.is_pdf then self.document:setImportedAnnotations(self.ui.annotation.annotations) end
    self.ui:handleEvent(Event:new("AnnotationsModified", { candidate, original }))
    UIManager:setDirty(self.dialog, "ui")
    return true, updated_index
end

function ReaderHighlight:ownedDeletionState(item)
    local owned = item.koreaderx_pdf_owned
    if not owned then return end
    assert(type(owned) == "table" and owned.version == 1 and type(owned.parts) == "table", "Invalid owned PDF provenance")
    local state = util.tableDeepCopy(self.ui.doc_settings:readSetting("koreaderx_pdf_import", { version = 1, tombstones = {} }))
    assert(type(state) == "table" and (not state.version or state.version == 1), "Unsupported PDF import metadata schema")
    state.version, state.tombstones = 1, state.tombstones or {}
    assert(type(state.tombstones) == "table", "Invalid PDF tombstone data")
    for _, parts in ipairs({ owned.parts, owned.pending and owned.pending.parts or {} }) do
        for _, part in ipairs(parts) do
            local tombstone = util.tableDeepCopy(part)
            tombstone.koreaderx_owned = true -- never relocate ownership to a coincident foreign source
            table.insert(state.tombstones, tombstone)
        end
    end
    return state
end

function ReaderHighlight:lookupWikipedia()
    if self.selected_text then
        self.ui:handleEvent(Event:new("LookupWikipedia", util.cleanupSelectedText(self.selected_text.text)))
    end
end

function ReaderHighlight:onHighlightSearch()
    logger.dbg("search highlight")
    -- First, if our dialog is still shown, close it.
    if self.highlight_dialog then
        UIManager:close(self.highlight_dialog)
        self.highlight_dialog = nil
    end
    self:highlightFromHoldPos()
    if self.selected_text then
        local text = util.cleanupSelectedText(self.selected_text.text)
        self.ui.search:searchText(text)
    end
end

function ReaderHighlight:lookupDict(index)
    logger.dbg("dictionary lookup highlight")
    self:highlightFromHoldPos()
    if self.selected_text then
        local boxes = index and self:getHighlightVisibleBoxes(index) or (self.selected_text.sboxes or self.selected_text.pboxes)
        local word_boxes
        if boxes ~= nil then
            word_boxes = {}
            for i, box in ipairs(boxes) do
                word_boxes[i] = self.view:pageToScreenTransform(self.selected_text.pos0.page, box)
            end
        end
        self.ui.dictionary:onLookupWord(util.cleanupSelectedText(self.selected_text.text), false, word_boxes, self)
    end
end

function ReaderHighlight:deleteHighlight(index)
    if not self:checkAnnotationEditingAllowed() then return false end
    logger.dbg("delete highlight", index)
    local item = self.ui.annotation.annotations[index]
    if not item then return false end
    if item.koreaderx_pdf_source then return self:commitImportedChange(index, nil, "delete") end
    local ok, state = pcall(self.ownedDeletionState, self, item)
    if not ok then
        UIManager:show(InfoMessage:new{ text = tostring(state) })
        return false
    end
    if self:writePdfAnnotation("delete", item) == false then return false end
    if state then self.ui.doc_settings:saveSetting("koreaderx_pdf_import", state) end
    self.ui.bookmark:removeItemByIndex(index)
    UIManager:setDirty(self.dialog, "ui")
    return true
end

function ReaderHighlight:addNote(text)
    self:showHighlightPrompt(function(index)
        if text then -- called from Translator to save translation to note
            self:clear()
        end
        self:editNote(index, true, text)
    end)
end

function ReaderHighlight:editNote(index, is_new_note, text)
    local note_updated_callback = function()
        if self.view.highlight.note_mark then -- refresh note marker
            UIManager:setDirty(self.dialog, "ui")
        end
    end
    self.ui.bookmark:setBookmarkNote(index, is_new_note, text, note_updated_callback)
end

function ReaderHighlight:editHighlightStyle(index)
    if not self:checkAnnotationEditingAllowed() then return false end
    local resolve, refresh = self:makeHighlightResolver(index)
    local item = self.ui.annotation.annotations[index]
    local style_selector
    style_selector = ButtonSelector:new{
        current_value = item.drawer,
        values = highlight_style,
        callback = function(value)
            if not self:checkAnnotationEditingAllowed() then return false end
            index = resolve()
            if not index then UIManager:close(style_selector); return end
            item = self.ui.annotation.annotations[index]
            if item.koreaderx_pdf_source then
                local candidate = util.tableDeepCopy(item)
                candidate.drawer = value
                local ok = self:commitImportedChange(index, candidate, "style")
                if ok then refresh(index) end
                return ok
            end
            local candidate = util.tableDeepCopy(item)
            candidate.drawer = value
            if self:commitOrdinaryChange(index, candidate) then refresh(index) end
        end,
        anchor = function()
            return self:_getDialogAnchor(style_selector, resolve())
        end,
    }
    UIManager:show(style_selector)
end

function ReaderHighlight:editHighlightColor(index)
    local resolve, refresh = self:makeHighlightResolver(index)
    local item = self.ui.annotation.annotations[index]
    local color_selector
    color_selector = ButtonSelector:new{
        current_value = item.color,
        values = self.highlight_colors,
        bg_colors = self:getHighlightColorList(),
        keep_open_on_apply = true,
        callback = function(value)
            local current = resolve()
            if not current then UIManager:close(color_selector); return end
            if self:setHighlightColor(current, value) then refresh(current) end
        end,
        anchor = function() return self:_getDialogAnchor(color_selector, resolve()) end,
    }
    UIManager:show(color_selector)
end

function ReaderHighlight:showHighlightPrompt(caller_callback, prompt)
    if self.highlight_dialog then
        UIManager:close(self.highlight_dialog)
        self.highlight_dialog = nil
    end
    if self.hold_pos and not self.selected_text then
        self:highlightFromHoldPos()
    end
    if not (self.selected_text and self.selected_text.pos0 and self.selected_text.pos1) then return end

    local do_highlight = function(select_color)
        if select_color then
            self:showHighlightPrompt(caller_callback, "color")
        else
            local index = self:saveHighlight(true)
            self:clear()
            if caller_callback and index then
                caller_callback(index)
            end
        end
    end

    prompt = prompt or G_reader_settings:readSetting("highlight_prompt")
    if prompt then
        if prompt == "color" then
            local color_selector
            color_selector = ButtonSelector:new{
                current_value = self.view.highlight.saved_color,
                values = self.highlight_colors,
                bg_colors = self:getHighlightColorList(),
                apply_current_value = true,
                callback = function(value)
                    self.selected_text.color = value
                    do_highlight()
                end,
                tap_close_callback = function()
                    do_highlight()
                end,
                anchor = function()
                    return self:_getDialogAnchor(color_selector)
                end,
            }
            UIManager:show(color_selector)
        else -- "style", "all"
            local style_selector
            style_selector = ButtonSelector:new{
                current_value = self.view.highlight.saved_drawer,
                values = highlight_style,
                apply_current_value = true,
                callback = function(value)
                    self.selected_text.drawer = value
                    do_highlight(prompt == "all" and self.selected_text.drawer ~= "invert")
                end,
                tap_close_callback = function()
                    do_highlight(prompt == "all" and self.selected_text.drawer ~= "invert")
                end,
                anchor = function()
                    return self:_getDialogAnchor(style_selector)
                end,
            }
            UIManager:show(style_selector)
        end
    else
        do_highlight()
    end
end

function ReaderHighlight:startSelection(index)
    if index then -- extend existing highlight
        UIManager:setDirty(self.dialog, "ui", self.view.flipping:getRefreshRegion())
    else -- new highlight
        index = self:saveHighlight()
        if not index then return false end
        self.ui.annotation.annotations[index].is_tmp = true
    end
    self.highlight_idx = index
    self.select_mode = true
end

function ReaderHighlight:extendSelection()
    -- item1 - starting fragment (saved), item2 - ending fragment (currently selected)
    -- new extended highlight includes item1, item2 and the text between them
    local item1 = self.ui.annotation.annotations[self.highlight_idx]
    local item2_pos0, item2_pos1 = self.selected_text.pos0, self.selected_text.pos1
    -- getting starting and ending positions, text and pboxes of extended highlight
    local new_pos0, new_pos1, new_text, new_pboxes, ext
    if self.ui.paging then
        local cur_page = self.hold_pos.page
        local is_reflow = self.ui.document.configurable.text_wrap
        -- pos0 and pos1 are not in order within highlights, hence sorting all
        local function comparePositions (pos1, pos2)
            return self.ui.document:comparePositions(pos1, pos2) == 1
        end
        local positions = {item1.pos0, item1.pos1, item2_pos0, item2_pos1}
        self.ui.document.configurable.text_wrap = 0 -- native positions
        table.sort(positions, comparePositions)
        new_pos0 = positions[1]
        new_pos1 = positions[4]
        local temp_pos0, temp_pos1
        if new_pos0.page == new_pos1.page then -- single-page highlight
            local text_boxes = self.ui.document:getTextFromPositions(new_pos0, new_pos1)
            new_text = text_boxes.text
            new_pboxes = text_boxes.pboxes
            temp_pos0, temp_pos1 = new_pos0, new_pos1
        else -- multi-page highlight
            new_text = ""
            ext = {}
            for page = new_pos0.page, new_pos1.page do
                local item = self:getExtendedHighlightPage(new_pos0, new_pos1, page)
                new_text = new_text .. item.text
                ext[page] = { -- for every page of multi-page highlight
                    pos0 = item.pos0,
                    pos1 = item.pos1,
                    pboxes = item.pboxes,
                }
                if page == cur_page then
                    temp_pos0, temp_pos1 = item.pos0, item.pos1
                end
            end
        end
        self.ui.document.configurable.text_wrap = is_reflow -- restore reflow
        -- draw
        self.view.highlight.temp[cur_page] = self.ui.document:getPageBoxesFromPositions(cur_page, temp_pos0, temp_pos1)
    else
        -- pos0 and pos1 are in order within highlights
        new_pos0 = self.ui.document:compareXPointers(item1.pos0, item2_pos0) == 1 and item1.pos0 or item2_pos0
        new_pos1 = self.ui.document:compareXPointers(item1.pos1, item2_pos1) == 1 and item2_pos1 or item1.pos1
        new_pboxes = self.document:getScreenBoxesFromPositions(new_pos0, new_pos1, true)
        -- true to draw
        new_text = self.ui.document:getTextFromXPointers(new_pos0, new_pos1, true)
    end
    if item1.koreaderx_pdf_source or item1.koreaderx_pdf_owned then
        self.selected_text = util.tableDeepCopy(item1)
        if item1.koreaderx_pdf_source then self.selected_text._koreaderx_extend_index = self.highlight_idx
        else
            self.selected_text._koreaderx_owned_extend_index = self.highlight_idx
            self.selected_text.is_extended = not item1.is_tmp
        end
        self.selected_text.pos0, self.selected_text.pos1 = new_pos0, new_pos1
        self.selected_text.page = new_pos0.page
        self.selected_text.text, self.selected_text.pboxes, self.selected_text.ext = new_text, new_pboxes, ext
        UIManager:setDirty(self.dialog, "ui")
        return
    end
    if self:deleteHighlight(self.highlight_idx) == false then return false end -- starting fragment
    self.selected_text = {
        is_extended = not item1.is_tmp,
        datetime = item1.datetime,
        drawer = item1.drawer,
        color = item1.color,
        note = item1.note,
        text = new_text,
        pos0 = new_pos0,
        pos1 = new_pos1,
        pboxes = new_pboxes,
        ext = ext,
    }
    UIManager:setDirty(self.dialog, "ui")
end

-- Calculates positions, text, pboxes of one page of selected multi-page highlight
-- (For pdf documents only, reflow mode must be off)
function ReaderHighlight:getExtendedHighlightPage(pos0, pos1, cur_page)
    local item = {}
    for page = pos0.page, pos1.page do
        if page == cur_page then
            local page_boxes = self.ui.document:getTextBoxes(page)
            if page == pos0.page then
                -- first page (from the start of highlight to the end of the page)
                item.pos0 = {
                    x = pos0.x,
                    y = pos0.y,
                }
                item.pos1 = {
                    x = page_boxes[#page_boxes][#page_boxes[#page_boxes]].x1,
                    y = page_boxes[#page_boxes][#page_boxes[#page_boxes]].y1,
                }
            elseif page ~= pos1.page then
                -- middle pages (full pages)
                item.pos0 = {
                    x = page_boxes[1][1].x0,
                    y = page_boxes[1][1].y0,
                }
                item.pos1 = {
                    x = page_boxes[#page_boxes][#page_boxes[#page_boxes]].x1,
                    y = page_boxes[#page_boxes][#page_boxes[#page_boxes]].y1,
                }
            else
                -- last page (from the start of the page to the end of highlight)
                item.pos0 = {
                    x = page_boxes[1][1].x0,
                    y = page_boxes[1][1].y0,
                }
                item.pos1 = {
                    x = pos1.x,
                    y = pos1.y,
                }
            end
            item.pos0.page = page
            item.pos1.page = page
            local text_boxes = self.ui.document:getTextFromPositions(item.pos0, item.pos1)
            item.text = text_boxes.text
            item.pboxes = text_boxes.pboxes
        end
    end
    return item
end

-- Returns the list of highlights in page.
-- The list includes full single-page highlights and parts of multi-page highlights.
-- (For pdf documents only)
function ReaderHighlight:getPageSavedHighlights(page)
    local idx_offset
    local highlights = {}
    for index, highlight in ipairs(self.ui.annotation.annotations) do
        if highlight.drawer and highlight.pos0.page <= page and page <= highlight.pos1.page then
            if idx_offset == nil then
                idx_offset = index - 1
            end
            if highlight.ext then -- multi-page highlight
                local item = self:getSavedExtendedHighlightPage(highlight, page, index)
                table.insert(highlights, item)
            else
                table.insert(highlights, highlight)
            end
        end
    end
    return highlights, idx_offset
end

-- Returns one page of saved multi-page highlight
-- (For pdf documents only)
function ReaderHighlight:getSavedExtendedHighlightPage(highlight, page, index)
    local item = {
        datetime = highlight.datetime,
        drawer   = highlight.drawer,
        color    = highlight.color or self.view.highlight.saved_color,
        text     = highlight.text,
        note     = highlight.note,
        page     = highlight.page,
        pos0     = highlight.ext[page].pos0,
        pos1     = highlight.ext[page].pos1,
        pboxes   = highlight.ext[page].pboxes,
        parent   = index,
        koreaderx_pdf_source = highlight.koreaderx_pdf_source,
        koreaderx_pdf_visual_override = highlight.koreaderx_pdf_visual_override,
    }
    item.pos0.zoom     = highlight.pos0.zoom
    item.pos0.rotation = highlight.pos0.rotation
    item.pos1.zoom     = highlight.pos0.zoom
    item.pos1.rotation = highlight.pos0.rotation
    return item
end

function ReaderHighlight:setDefaultHighlightColor(value)
    self.view.highlight.saved_color = value
    G_reader_settings:saveSetting("highlight_color", value)
    self.ui.doc_settings:saveSetting("highlight_color", value)
    self:setSelectionColor()
end

function ReaderHighlight:setAITranslateEnabled(enabled)
    G_reader_settings:saveSetting("ai_translate", enabled and "1" or "0")
    G_reader_settings:saveSetting("default_highlight_action", enabled and "ai_translate" or "highlight")
    self.view.highlight.disabled = false
end

function ReaderHighlight:translateWithAssistant()
    local PluginLoader = require("pluginloader")
    local plugin = PluginLoader:getPluginInstance("assistant")
    if not plugin then
        UIManager:show(Notification:new{ text = _("AI Assistant plugin not available") })
        return
    end
    if type(plugin.isConfigured) == "function" and not plugin:isConfigured() then return end
    local dialog = plugin.assistant_dialog
    if not dialog or type(dialog.showCustomPrompt) ~= "function" then
        UIManager:show(Notification:new{ text = _("AI Assistant is not configured or its interface is unavailable.") })
        return
    end
    if not (self.selected_text and type(self.selected_text.text) == "string") then return end
    local text = util.stripPunctuation(util.cleanupSelectedText(self.selected_text.text))
    if text == "" then return end
    local token = self.koreaderx_reader_token or {}
    self.koreaderx_reader_token = token
    require("ui/network/manager"):runWhenOnline(function()
        if self.koreaderx_reader_token ~= token or PluginLoader:getPluginInstance("assistant") ~= plugin then return end
        require("ui/trapper"):wrap(function()
            if self.koreaderx_reader_token ~= token or plugin.assistant_dialog ~= dialog then return end
            dialog:showCustomPrompt(text, "translate")
        end)
    end)
end

function ReaderHighlight:onCloseWidget()
    self.koreaderx_reader_token = nil
end

function ReaderHighlight:showHighlightDialog(index)
    local resolve, refresh = self:makeHighlightResolver(index)
    local item = self.ui.annotation.annotations[index]
    if not item then return end
    local dialog
    local buttons = { {}, {} }
    for _, color in ipairs(self.highlight_colors) do
        buttons[1][#buttons[1] + 1] = {
            text = color[1], background = self:getHighlightColor(color[2]),
            callback = function()
                local current = resolve()
                if not current then UIManager:close(dialog); return end
                if self:setHighlightColor(current, color[2]) then refresh(current) end
            end,
        }
    end
    buttons[2] = {
        { text = "\u{F48E}", callback = function()
            local current = resolve()
            if not current or self:deleteHighlight(current) ~= false then UIManager:close(dialog) end
        end },
        { text = _("More…"), callback = function()
            UIManager:close(dialog)
            local current = resolve()
            if current then self:showFullHighlightDialog(current) end
        end },
    }
    dialog = ButtonDialog:new{
        name = "koreaderx_highlight_palette", buttons = buttons,
        anchor = function() return self:_getDialogAnchor(dialog, resolve()) end,
    }
    UIManager:show(dialog)
end

function ReaderHighlight:setHighlightColor(index, value)
    if not self:checkAnnotationEditingAllowed() then return false end
    local item = self.ui.annotation.annotations[index]
    if not item then return false end
    if item.koreaderx_pdf_source then
        local candidate = util.tableDeepCopy(item)
        candidate.color = value
        if not self:commitImportedChange(index, candidate, "color") then return false end
    else
        local candidate = util.tableDeepCopy(item)
        candidate.color = value
        if not self:commitOrdinaryChange(index, candidate) then return false end
    end
    self:setDefaultHighlightColor(value)
    return true
end

-- Commit a candidate before replacing live annotations. All native writes run
-- against a snapshot, including boundary/style changes and multi-page parts.
function ReaderHighlight:commitImportedChange(index, candidate, action)
    if not self:checkAnnotationEditingAllowed() then return false end
    local Transaction = require("document/pdfannotationtransaction")
    local original = self.ui.annotation.annotations[index]
    local updated_index = index
    local data = util.tableDeepCopy(self.ui.doc_settings.data)
    data.annotations = util.tableDeepCopy(self.ui.annotation.annotations)
    data.koreaderx_pdf_import = data.koreaderx_pdf_import or { version = 1, tombstones = {} }
    if type(data.koreaderx_pdf_import) ~= "table" or (data.koreaderx_pdf_import.version and data.koreaderx_pdf_import.version ~= 1) then
        return false, "Unsupported PDF import metadata schema"
    end
    data.koreaderx_pdf_import.tombstones = data.koreaderx_pdf_import.tombstones or {}
    if type(data.koreaderx_pdf_import.tombstones) ~= "table" then return false, "Invalid PDF tombstone data" end
    local ok, err = pcall(function()
        self.document:validateImportedAnnotation(original)
        if action == "delete" or action == "detach" then
            for _, part in ipairs(original.koreaderx_pdf_source.parts) do
                table.insert(data.koreaderx_pdf_import.tombstones, util.tableDeepCopy(part))
            end
            if action == "delete" then table.remove(data.annotations, index)
            else data.annotations[index] = candidate end
        else
            candidate.datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
            if action == "geometry" and candidate.page ~= original.page then
                candidate.chapter = self.ui.toc:getTocTitleByPage(candidate.page)
                table.remove(data.annotations, index)
                local container = self.ui.annotation:extend{ annotations = data.annotations }
                updated_index = container:addItem(candidate)
            else
                data.annotations[index] = candidate
            end
        end
        if self.highlight_write_into_pdf then
            self.document:commitImportedAnnotation(self.ui.doc_settings, data, candidate or util.tableDeepCopy(original), action)
        else
            if candidate and action ~= "note" then
                candidate.koreaderx_pdf_visual_override = candidate.koreaderx_pdf_visual_override or {}
                if action == "appearance" then
                    candidate.koreaderx_pdf_visual_override.color, candidate.koreaderx_pdf_visual_override.style = true, true
                else
                    candidate.koreaderx_pdf_visual_override[action] = true
                end
            end
            Transaction.commitMetadata(self.ui.doc_settings, data)
        end
    end)
    if not ok then
        logger.warn("KOReaderX annotation transaction failed:", err)
        UIManager:show(InfoMessage:new{ text = _("The annotation change could not be completed. PDF/metadata may need recovery; transaction backups were retained.") .. "\n" .. tostring(err) })
        return false
    end
    self.ui.annotation.annotations = data.annotations
    self.document:setImportedAnnotations(data.annotations)
    if action == "delete" then
        self.ui:handleEvent(Event:new("AnnotationsModified", { original, index_modified = -index,
            nb_highlights_added = original.note and 0 or -1, nb_notes_added = original.note and -1 or 0 }))
        if not self.highlight_write_into_pdf then
            UIManager:show(Notification:new{ text = _("Removed from KOReader. The original annotation remains in the PDF.") })
        end
    else
        self.ui:handleEvent(Event:new("AnnotationsModified", { candidate, index_modified = updated_index }))
    end
    self.view.footer:maybeUpdateFooter()
    UIManager:setDirty(self.dialog, "ui")
    return true, updated_index
end

-- Native originals remain intact. Geometry is display data; identity and raw
-- snapshots are used for dedup and all future writes, never geometry alone.
function ReaderHighlight:importEmbeddedAnnotations(annotations, replace_highlights, restore_deleted)
    if not self:checkAnnotationEditingAllowed() then return nil, "PDF transaction recovery is required" end
    local Annotation = require("document/pdfannotations")
    local Transaction = require("document/pdfannotationtransaction")
    local data = util.tableDeepCopy(self.ui.doc_settings.data)
    data.koreaderx_pdf_import = data.koreaderx_pdf_import or { version = 1, tombstones = {} }
    if type(data.koreaderx_pdf_import) ~= "table" or (data.koreaderx_pdf_import.version and data.koreaderx_pdf_import.version ~= 1) then
        return nil, "Unsupported PDF import metadata schema"
    end
    data.koreaderx_pdf_import.tombstones = data.koreaderx_pdf_import.tombstones or {}
    if type(data.koreaderx_pdf_import.tombstones) ~= "table" then return nil, "Invalid PDF tombstone data" end
    local existing = self.ui.annotation.annotations
    if replace_highlights then
        existing = {}
        for _, item in ipairs(self.ui.annotation.annotations) do
            if not item.drawer then existing[#existing + 1] = item end
        end
    end
    if replace_highlights or restore_deleted then data.koreaderx_pdf_import.tombstones = {} end
    local added, skipped, invalid, conflicts
    local ok, err = pcall(function()
        data.annotations, added, skipped, invalid, conflicts = Annotation.import(annotations,
            existing, data.koreaderx_pdf_import.tombstones, function(page, annot)
                local first, last = annot.boxes[1], annot.boxes[#annot.boxes]
                local pos0 = { page = page, rotation = Screen:getRotationMode(), zoom = self.ui.zooming:getZoom(page),
                    x = first.x + math.min(1, first.w / 4), y = first.y + math.min(1, first.h / 4) }
                local pos1 = { page = page, rotation = pos0.rotation, zoom = pos0.zoom,
                    x = last.x + last.w - math.min(2, last.w / 4), y = last.y + last.h - math.min(2, last.h / 4) }
                local selected = self.document:getTextFromPositions(pos0, pos1)
                return { page = page, pos0 = pos0, pos1 = pos1, pboxes = util.tableDeepCopy(annot.boxes),
                    text = selected and type(selected.text) == "string" and util.cleanupSelectedText(selected.text) or "",
                    note = annot.contents ~= "" and annot.contents or nil,
                    author = annot.author,
                    drawer = Annotation.drawers[annot.type],
                    color = Annotation.nearestColor(annot.color_rgb, Blitbuffer.HIGHLIGHT_COLORS),
                    chapter = self.ui.toc:getTocTitleByPage(page) }
            end)
        -- addItem supplies upstream ordering/date/page-reference semantics,
        -- using an independent candidate container (not live annotations).
        local initial = {}
        for index = 1, #existing do initial[index] = data.annotations[index] end
        local container = self.ui.annotation:extend{ annotations = initial }
        for _, item in ipairs(added) do container:addItem(item) end
        data.annotations = container.annotations
        data.koreaderx_pdf_import.imported_mtime = require("libs/libkoreader-lfs").attributes(self.document.file, "modification")
        data.koreaderx_pdf_import.seen_mtime = data.koreaderx_pdf_import.imported_mtime
        Transaction.commitMetadata(self.ui.doc_settings, data)
    end)
    if not ok then return nil, tostring(err) end
    self.ui.annotation.annotations = data.annotations
    self.document:setImportedAnnotations(data.annotations)
    for _, item in ipairs(added) do
        local index = self.ui.annotation:getItemIndex(item)
        self.ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = item.note and 0 or 1,
            nb_notes_added = item.note and 1 or 0, index_modified = index }))
    end
    self.view.footer:maybeUpdateFooter()
    UIManager:setDirty(self.dialog, "ui")
    return #added, skipped, invalid, conflicts
end

function ReaderHighlight:resetMetadatafile()
    if not (self.document.supportsEmbeddedAnnotations and self.document:supportsEmbeddedAnnotations()
        and self.document.configurable.text_wrap == 0) then return end
    local entries, count = {}, 0
    for _, item in ipairs(self.ui.annotation.annotations) do
        if item.drawer then
            count = count + 1
            entries[#entries + 1] = tostring(count) .. ". [" .. tostring(item.page) .. "] "
                .. (item.koreaderx_pdf_source and _("Imported") or _("Local / legacy; may exist only in KOReader"))
                .. "\n" .. (item.text or "") .. (item.note and "\n" .. item.note or "")
        end
    end
    local viewer
    viewer = TextViewer:new{
        title = _("Replace KOReader highlights from PDF: preview"),
        text = _("The following highlights and notes will be removed from KOReader metadata. Page bookmarks and PDF originals will remain. A complete sidecar backup is kept before replacement.")
            .. "\n\n" .. table.concat(entries, "\n\n"),
        buttons_table = {{
            { text = _("Cancel"), callback = function() UIManager:close(viewer) end },
            { text = _("Replace…"), callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Replace all %1 listed highlights and reset the deleted-source list?"), count),
                    ok_callback = function()
                        local ok, annotations = pcall(self.document.getEmbeddedAnnotations, self.document)
                        if not ok then UIManager:show(InfoMessage:new{ text = tostring(annotations) }); return end
                        local imported, err = self:importEmbeddedAnnotations(annotations or {}, true)
                        if not imported then UIManager:show(InfoMessage:new{ text = tostring(err) }); return end
                        UIManager:close(viewer)
                        UIManager:show(Notification:new{ text = T(_("Replaced metadata; imported %1 PDF annotations. The previous sidecar is backed up."), imported) })
                    end,
                })
            end },
        }},
    }
    UIManager:show(viewer)
end

function ReaderHighlight:reimportDeletedPdfAnnotations()
    local state = self.ui.doc_settings:readSetting("koreaderx_pdf_import", {})
    local tombstones = state.tombstones or {}
    local lines = {}
    for _, part in ipairs(tombstones) do
        lines[#lines + 1] = T(_("Page %1, PDF object %2: %3"), part.page, part.num, part.raw.contents or "")
    end
    local viewer
    viewer = TextViewer:new{
        title = _("Reimport deleted PDF annotations: preview"), text = table.concat(lines, "\n"),
        buttons_table = {{
            { text = _("Cancel"), callback = function() UIManager:close(viewer) end },
            { text = _("Reimport listed annotations"), callback = function()
                local ok, annotations = pcall(self.document.getEmbeddedAnnotations, self.document)
                if not ok then UIManager:show(InfoMessage:new{ text = tostring(annotations) }); return end
                local count, err = self:importEmbeddedAnnotations(annotations or {}, false, true)
                if not count then UIManager:show(InfoMessage:new{ text = tostring(err) }); return end
                UIManager:close(viewer)
                UIManager:show(Notification:new{ text = T(_("Imported %1 annotations."), count) })
            end },
        }},
    }
    UIManager:show(viewer)
end

function ReaderHighlight:requestPdfImport()
    if not (self.document.supportsEmbeddedAnnotations and self.document:supportsEmbeddedAnnotations() and self.document.configurable.text_wrap == 0) then return end
    UIManager:show(ConfirmBox:new{
        text = _("Import embedded PDF annotations? Existing KOReader highlights and the PDF originals will be kept."),
        ok_callback = function() self.ui.bookmark:importEmbeddedAnnotations() end,
    })
end

function ReaderHighlight:onPdfAnnotationsReady()
    if not (self.document.supportsEmbeddedAnnotations and self.document:supportsEmbeddedAnnotations()) then return end
    self.document.koreaderx_owned_settings = self.ui.doc_settings
    self.document:reconcileOwnedProvenance(self.ui.annotation.annotations)
    self.document:setImportedAnnotations(self.ui.annotation.annotations)
    if self.document.configurable.text_wrap ~= 0 then return end
    local mtime = require("libs/libkoreader-lfs").attributes(self.document.file, "modification")
    local state = self.ui.doc_settings:readSetting("koreaderx_pdf_import", {})
    if type(state) ~= "table" or (state.version and state.version ~= 1) then return end
    if mtime and state.seen_mtime ~= mtime then
        UIManager:show(ConfirmBox:new{
            text = _("The PDF is new or has changed. Import its embedded annotations without removing existing highlights?"),
            ok_callback = function() self.ui.bookmark:importEmbeddedAnnotations() end,
            cancel_callback = function()
                state = util.tableDeepCopy(state)
                state.version, state.seen_mtime = 1, mtime
                state.tombstones = state.tombstones or {}
                self.ui.doc_settings:saveSetting("koreaderx_pdf_import", state)
            end,
        })
    end
end

function ReaderHighlight:onReadSettings(config)
    self.view.highlight.saved_drawer = config:readSetting("highlight_drawer")
        or G_reader_settings:readSetting("highlight_drawing_style") or self.view.highlight.saved_drawer
    self.view.highlight.saved_color = config:readSetting("highlight_color")
        or G_reader_settings:readSetting("highlight_color") or self.view.highlight.saved_color
    self.view.highlight.disabled = G_reader_settings:readSetting("default_highlight_action") == "nothing"
    self:setSelectionColor()
    self.allow_corner_scroll = G_reader_settings:nilOrTrue("highlight_corner_scroll")

    -- panel zoom settings isn't supported in EPUB
    if self.ui.paging then
        if self.document.is_pdf and self.document:_checkIfWritable() then
            if config:has("highlight_write_into_pdf") then
                self.highlight_write_into_pdf = config:isTrue("highlight_write_into_pdf") -- true or false
            else
                self.highlight_write_into_pdf = G_reader_settings:readSetting("highlight_write_into_pdf") -- true or nil
            end
        end
        local ext = util.getFileNameSuffix(self.ui.document.file)
        G_reader_settings:initializeExtSettings("panel_zoom_enabled", {cbz = true, cbt = true})
        G_reader_settings:initializeExtSettings("panel_zoom_fallback_to_text_selection", {pdf = true})
        if config:has("panel_zoom_enabled") then
            self.panel_zoom_enabled = config:isTrue("panel_zoom_enabled")
        else
            self.panel_zoom_enabled = G_reader_settings:getSettingForExt("panel_zoom_enabled", ext) or false
        end
        if config:has("panel_zoom_fallback_to_text_selection") then
            self.panel_zoom_fallback_to_text_selection = config:isTrue("panel_zoom_fallback_to_text_selection")
        else
            self.panel_zoom_fallback_to_text_selection = G_reader_settings:getSettingForExt("panel_zoom_fallback_to_text_selection", ext) or false
        end
    end
end

function ReaderHighlight:setSelectionColor()
    if self.ui.paging then return end
    local color = self.view.highlight.saved_drawer ~= "invert"
        and G_reader_settings:isTrue("highlight_selection_use_highlight_color")
        and Blitbuffer.HIGHLIGHT_COLORS[self.view.highlight.saved_color]
    if color then
        if Screen.night_mode then
            local r, g, b = color:match("#(..)(..)(..)")
            color = string.format("#%02x%02x%02x", 255 - tonumber(r, 16), 255 - tonumber(g, 16), 255 - tonumber(b, 16))
        end
    else -- gray
        local lighten_factor = G_reader_settings:readSetting("highlight_selection_lighten_factor") or 0.2
        if lighten_factor == 0 then
            color = "#FFFFFF"
        elseif lighten_factor == 1 then
            color = "#000000"
        else
            color = string.format("%X", math.floor(256 * (1 - lighten_factor)))
            color = "#" .. color:rep(3)
        end
    end
    self.document._document:setStringProperty("crengine.highlight.selection.color", color)
end

function ReaderHighlight:onUpdateHoldPanRate()
    self:setupTouchZones()
end

function ReaderHighlight:onSaveSettings()
    self.ui.doc_settings:saveSetting("highlight_drawer", self.view.highlight.saved_drawer)
    self.ui.doc_settings:saveSetting("highlight_color", self.view.highlight.saved_color)
    self.ui.doc_settings:saveSetting("highlight_write_into_pdf", self.highlight_write_into_pdf)
    self.ui.doc_settings:saveSetting("panel_zoom_enabled", self.panel_zoom_enabled)
end

function ReaderHighlight:onClose(keep_highlight)
    if self.highlight_dialog then
        UIManager:close(self.highlight_dialog)
        self.highlight_dialog = nil
    end
    -- clear highlighted text
    if not keep_highlight then
        self:clear()
    end
end

return ReaderHighlight
