-- luacheck: globals os
describe("KOReaderX Android companion data isolation", function()
    local util, ffiutil, lfs, saved_android, saved_getenv, directory
    local private, external, production, storage
    local function write(path, data)
        local f = assert(io.open(path, "w")); f:write(data or "original"); f:close()
    end
    local function loadStorage(name, debuggable, home)
        package.loaded.android = {
            getPackageName = function() return name end,
            isDebuggable = function() return debuggable end,
            getTestDataPath = function() return private end,
            getExternalStoragePath = function() return external end,
            LOGI = function() end,
        }
        os.getenv = function(key)
            if key == "KO_HOME" then return home end
            return saved_getenv(key)
        end
        local result = dofile("datastorage.lua")
        os.getenv, package.loaded.android = saved_getenv, saved_android
        return result
    end
    setup(function()
        require("commonrequire")
        util, ffiutil, lfs = require("util"), require("ffi/util"), require("libs/libkoreader-lfs")
        saved_android, saved_getenv = package.loaded.android, os.getenv
    end)
    before_each(function()
        directory = os.tmpname(); os.remove(directory); util.makePath(directory)
        private, external, production = directory .. "/app_koreaderx-test", directory .. "/shared", directory .. "/production"
        util.makePath(private); util.makePath(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v"); util.makePath(production)
        storage = loadStorage("org.koreader.launcher.koreaderxtest", true, production)
    end)
    after_each(function()
        os.getenv, package.loaded.android = saved_getenv, saved_android
        os.remove(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/link.pdf") -- purgeDir follows symlinks; remove this test link first.
        assert(ffiutil.purgeDir(directory))
    end)
    it("uses Context private data despite KO_HOME and derives every data root from it", function()
        assert.is_true(storage:isIsolatedTestProfile())
        assert.equals(private, storage:getDataDir())
        assert.equals(private .. "/settings", storage:getSettingsDir())
        assert.equals(private .. "/docsettings", storage:getDocSettingsDir())
        assert.equals(private .. "/hashdocsettings", storage:getDocSettingsHashDir())
        for _, dir in ipairs({ "cache", "plugins", "settings", "data", "screenshots" }) do
            assert.equals("directory", lfs.attributes(private .. "/" .. dir, "mode"))
            assert.is_nil(lfs.attributes(production .. "/" .. dir))
        end
    end)
    it("keeps release and existing debug packages on their established storage policy", function()
        for _, name in ipairs({"org.koreader.launcher", "org.koreader.launcher.debug"}) do
            local existing = loadStorage(name, true)
            assert.is_false(existing:isIsolatedTestProfile())
            assert.equals(external .. "/koreader", existing:getDataDir())
            assert.equals(production, loadStorage(name, true, production):getDataDir())
        end
    end)
    it("rejects sibling names, parent traversal and symlinks to production books", function()
        local book = external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/book.pdf"
        write(book); write(production .. "/original.pdf")
        util.makePath(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v-other"); write(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v-other/book.pdf")
        write(private .. "/private.epub")
        assert(lfs.link(production .. "/original.pdf", external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/link.pdf", true))
        assert.is_true(storage:isTestPathAllowed(book))
        assert.is_true(storage:isTestPathAllowed(private .. "/private.epub"))
        assert.is_false(storage:isTestPathAllowed(production .. "/original.pdf"))
        assert.is_false(storage:isTestPathAllowed(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/link.pdf"))
        assert.is_false(storage:isTestPathAllowed(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/../test-other/book.pdf"))
        assert.is_false(storage:isTestPathAllowed(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v-other/book.pdf"))
    end)
    it("refuses nested old absolute settings references and configures only private plugins", function()
        local policy = require("androidtestprofile")
        local settings = require("luasettings"):wrap{
            home_dir = production, document_metadata_folder = "doc", extra_plugin_paths = {production .. "/plugins"},
            footer = { container_height = 31, highlight_navigation = true },
        }
        policy.prepare(settings, storage)
        assert.equals(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v", settings:readSetting("home_dir"))
        assert.is_true(settings:isTrue("lock_home_folder"))
        assert.equals("dir", settings:readSetting("document_metadata_folder"))
        assert.same({ private .. "/plugins" }, settings:readSetting("extra_plugin_paths"))
        assert.equals(31, settings:readSetting("footer").container_height)
        settings:saveSetting("lastfile", production .. "/original.pdf")
        assert.has_error(function() policy.prepare(settings, storage) end)
        assert.is_nil(policy.audit({ nested = { [production .. "/original.pdf"] = true } }, {private}))
        assert.is_nil(policy.audit({lastfile = private .. "/../production/original.pdf"}, {private}))
    end)
    it("saves and reopens private metadata without reading or deleting sibling metadata", function()
        local old_storage = package.loaded.datastorage
        package.loaded.datastorage = storage
        local docsettings = dofile("frontend/docsettings.lua")
        package.loaded.datastorage = old_storage
        local book = external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/book.epub"
        write(book)
        util.makePath(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/book.sdr")
        local sibling = external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/book.sdr/metadata.epub.lua"
        local legacy = book .. ".kpdfview.lua"
        write(sibling, 'return { marker = "production-sibling" }')
        write(legacy, 'return { marker = "production-legacy" }')
        local settings = docsettings:open(book)
        assert.is_nil(settings:readSetting("marker"))
        for _, location in ipairs({"doc", "dir", "hash"}) do
            local path = docsettings:getSidecarDir(book, location)
            assert.equals(private .. "/docsettings/", path:sub(1, #private + 13))
        end
        assert(lfs.link(book, external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/alias.epub", true))
        assert.equals(docsettings:getSidecarDir(book),
            docsettings:getSidecarDir(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/alias.epub"))
        os.remove(external .. "/Books/test/KOReaderX_S10_ZWSqRJ0v/alias.epub")
        settings:saveSetting("marker", "private-only")
        assert.truthy(settings:flush())
        assert.equals("private-only", docsettings:open(book):readSetting("marker"))
        assert.equals("production-sibling", dofile(sibling).marker)
        assert.equals("production-legacy", dofile(legacy).marker)
        settings:purge()
        assert.equals("file", lfs.attributes(sibling, "mode"))
        assert.equals("file", lfs.attributes(legacy, "mode"))
    end)
    it("stops a stale document-open request before its provider is invoked", function()
        local existing = require("datastorage")
        local old = existing.isTestPathAllowed
        existing.isTestPathAllowed = function(_, path) return storage:isTestPathAllowed(path) end
        local registry = require("document/documentregistry")
        local provider = { new = function() error("outside provider was invoked") end }
        local ok, document = pcall(registry.openDocument, registry, production .. "/original.pdf", provider)
        existing.isTestPathAllowed = old
        assert.is_true(ok)
        assert.is_nil(document)
    end)
end)
