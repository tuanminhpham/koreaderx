describe("KOReaderX footer migration", function()
    local Migration = require("ui/data/koreaderx_footer_migration")
    local function settings(data)
        return {
            data = data,
            readSetting = function(self, key) return self.data[key] end,
            saveSetting = function(self, key, value) self.data[key] = value end,
        }
    end
    local function device(enabled)
        return {
            hasFastWifiStatusQuery = function() return enabled end,
            hasFrontlight = function() return enabled end,
            hasNaturalLight = function() return enabled end,
            hasBattery = function() return enabled end,
        }
    end
    for _, enabled in ipairs({ true, false }) do
        for _, custom_order in ipairs({ true, false }) do
            it("preserves the selected old named mode with capabilities=" .. tostring(enabled)
                    .. " and custom order=" .. tostring(custom_order), function()
                local old_index = custom_order and 1 or (enabled and 20 or 16)
                local original_order = custom_order and {
                    [0] = "off", "highlight_navigation", "time", "frontlight", "wifi_status",
                } or nil
                local old_footer = {
                    highlight_navigation = true, container_height = 31, reclaim_height = false,
                    order = original_order,
                }
                local s = settings({ footer = old_footer, reader_footer_mode = old_index })
                assert.is_true(Migration.migrate(s, device(enabled)))
                assert.are.equal("highlight_navigation", s.data.footer.order[s.data.reader_footer_mode])
                assert.are.equal(31, s.data.footer.container_height)
                assert.is_false(s.data.footer.reclaim_height)
                assert.are.equal("highlight_navigation", s.data.koreaderx_footer_v0.selected_name)
                assert.are.same(old_footer, s.data.koreaderx_footer_v0.footer)
                assert.are.equal(original_order, old_footer.order)
                local migrated_footer, snapshot = s.data.footer, s.data.koreaderx_footer_v0
                assert.is_true(Migration.migrate(s, device(enabled)))
                assert.are.equal(migrated_footer, s.data.footer)
                assert.are.equal(snapshot, s.data.koreaderx_footer_v0)
                local counts = {}
                for _, name in pairs(s.data.footer.order) do counts[name] = (counts[name] or 0) + 1 end
                assert.are.equal(1, counts.highlight_navigation)
                assert.is_nil(counts.dynamic_filler)
                assert.is_nil(counts.additional_content)
                if not enabled then assert.is_nil(counts.frontlight) end
            end)
        end
    end
    it("preserves non-HN modes and explicit HN disabled", function()
        local s = settings({ footer = { highlight_navigation = false }, reader_footer_mode = 3 })
        assert.is_true(Migration.migrate(s, device(true)))
        assert.are.equal("time", s.data.footer.order[3])
        assert.is_false(s.data.footer.highlight_navigation)
    end)
    it("does not remap an upstream profile or populate a new profile as legacy", function()
        local footer = { order = { [0] = "off", "dynamic_filler", "additional_content" } }
        local s = settings({ footer = footer, reader_footer_mode = 1 })
        assert.is_true(Migration.migrate(s, device(true)))
        assert.are.equal(footer, s.data.footer)
        assert.are.equal(1, s.data.reader_footer_mode)
        assert.is_nil(s.data.koreaderx_footer_v0)
        local fresh = settings({})
        assert.is_true(Migration.migrate(fresh, device(true)))
        assert.is_nil(fresh.data.footer)
        assert.are.equal(1, fresh.data.koreaderx_settings_schema)
    end)
    it("rejects an unresolved old mode before changing any data", function()
        local footer = { highlight_navigation = true }
        local s = settings({ footer = footer, reader_footer_mode = 50 })
        local ok, message = Migration.migrate(s, device(true))
        assert.is_nil(ok)
        assert.is_truthy(message:find("cannot resolve", 1, true))
        assert.are.equal(footer, s.data.footer)
        assert.are.equal(50, s.data.reader_footer_mode)
        assert.is_nil(s.data.koreaderx_footer_v0)
        assert.is_nil(s.data.koreaderx_settings_schema)
    end)
end)
