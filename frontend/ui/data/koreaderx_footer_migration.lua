-- KOReaderX v2024.11 stored reader_footer_mode as a device-filtered order index.
-- Keep the old named order; target modes are appended by ReaderFooter afterwards.
local Migration = {}

local old_modes = {
    [0] = "off", "page_progress", "pages_left_book", "time", "pages_left",
    "battery", "percentage", "book_time_to_read", "chapter_time_to_read",
    "frontlight", "mem_usage", "wifi_status", "book_title", "book_chapter",
    "bookmark_count", "chapter_progress", "frontlight_warmth", "custom_text",
    "book_author", "page_turning_inverted", "highlight_navigation",
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

function Migration.migrate(settings, device)
    if settings:readSetting("koreaderx_settings_schema") then return true end
    local footer = settings:readSetting("footer")
    local saved_mode = settings:readSetting("reader_footer_mode")
    local is_fork = type(footer) == "table" and footer.highlight_navigation ~= nil
        or settings:readSetting("highlight_navigation_enable_tap") ~= nil
        or settings:readSetting("ai_translate") ~= nil
    -- Profiles without a fork marker keep the upstream mode numbering. New
    -- profiles are marked before upstream migrations populate default tables.
    if not is_fork then
        settings:saveSetting("koreaderx_settings_schema", 1)
        return true
    end
    if footer ~= nil and type(footer) ~= "table" then
        return nil, "KOReaderX footer migration: invalid footer settings; restore the profile backup"
    end
    footer = footer or {}
    local enabled = {}
    for _, name in pairs(old_modes) do enabled[name] = true end
    enabled.wifi_status = device:hasFastWifiStatusQuery()
    enabled.frontlight = device:hasFrontlight()
    enabled.battery = device:hasBattery()
    enabled.frontlight_warmth = device:hasNaturalLight()
    local order, seen, length = {}, {}, 0
    local function append(name)
        if enabled[name] and not seen[name] then
            order[length], seen[name] = name, true
            length = length + 1
        end
    end
    if footer.order ~= nil then
        if type(footer.order) ~= "table" then
            return nil, "KOReaderX footer migration: invalid named order; restore the profile backup"
        end
        for i = 0, #footer.order do append(footer.order[i]) end
    end
    for i = 0, #old_modes do append(old_modes[i]) end
    if saved_mode ~= nil and (type(saved_mode) ~= "number" or not order[saved_mode]) then
        return nil, "KOReaderX footer migration: cannot resolve the old mode index; restore the profile backup"
    end
    -- Nothing is changed until every input is validated. Keep a named snapshot
    -- for inspection; the full pre-upgrade profile is still the rollback source.
    settings:saveSetting("koreaderx_footer_v0", {
        footer = copy(footer), reader_footer_mode = saved_mode,
        selected_name = saved_mode and order[saved_mode] or nil,
    })
    local migrated = copy(footer)
    migrated.order = order
    settings:saveSetting("footer", migrated)
    settings:saveSetting("koreaderx_settings_schema", 1)
    return true
end

return Migration
