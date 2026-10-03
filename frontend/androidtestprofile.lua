-- Settings policy for the dedicated Android test package only.
-- This is not a sandbox for arbitrary Lua plugins or imported settings code.
local TestProfile = {}

local function inside(path, root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- Refuse stale absolute references in copied settings before migrations/plugins run.
-- Copying a whole production profile is intentionally unsupported: prepare an audited
-- preferences-only copy, with book paths remapped to Books/test, outside the app first.
function TestProfile.audit(data, roots, seen)
    if type(data) == "string" and data:sub(1, 1) == "/" then
        if data:find("/../", 1, true) or data:sub(-3) == "/.." then
            return nil, "parent traversal in copied test settings"
        end
        for _, root in ipairs(roots) do
            if inside(data, root) then return true end
        end
        return nil, "external absolute path in copied test settings"
    elseif type(data) == "table" then
        seen = seen or {}
        if seen[data] then return true end
        seen[data] = true
        for key, value in pairs(data) do
            local ok, err = TestProfile.audit(key, roots, seen)
            if not ok then return nil, err end
            ok, err = TestProfile.audit(value, roots, seen)
            if not ok then return nil, err end
        end
    end
    return true
end

function TestProfile.prepare(settings, storage)
    local profile, books = storage:getDataDir(), storage:getTestBooksDir()
    -- These policies cannot be overridden by an old profile or the shared plugin path.
    settings:saveSetting("home_dir", books)
    settings:saveSetting("lock_home_folder", true)
    settings:saveSetting("document_metadata_folder", "dir")
    settings:saveSetting("extra_plugin_paths", { profile .. "/plugins" })
    local books_alias = "/sdcard" .. assert(books:match("(/Books/test/[^/]+)$"))
    local roots = { profile, books, books_alias }
    -- Android may return /data/user/0 from Context while QuickStart/realpath
    -- stores /data/data in lastfile. Accept only this companion alias, and only
    -- when the actual filesystem resolves it to the same private profile.
    local profile_alias = "/data/data/org.koreader.launcher.koreaderxtest/app_koreaderx-test"
    local ffiutil = require("ffi/util")
    local canonical_profile = ffiutil.realpath(profile)
    local same_profile = canonical_profile and ffiutil.realpath(profile_alias) == canonical_profile
    if not same_profile then
        -- Android also exposes these paths through bind mounts, for which
        -- realpath strings may differ. Require the same existing directory.
        local lfs = require("libs/libkoreader-lfs")
        local context_attr, alias_attr = lfs.attributes(profile), lfs.attributes(profile_alias)
        same_profile = context_attr and alias_attr
            and context_attr.mode == "directory" and alias_attr.mode == "directory"
            and context_attr.dev ~= nil and context_attr.ino ~= nil
            and context_attr.dev == alias_attr.dev and context_attr.ino == alias_attr.ino
    end
    if same_profile then roots[#roots + 1] = profile_alias end
    local ok, err = TestProfile.audit(settings.data, roots)
    assert(ok, err)
end

return TestProfile
