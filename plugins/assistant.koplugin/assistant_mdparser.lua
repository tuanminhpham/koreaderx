-- markdown parser wrapper module
-- This module provides a simple interface to use hoedown (C binding of full features markdown)
-- or the pure Lua implementation of markdown.lua (building on KOReader)
local Parser = nil

local logger = require("logger")
local plugin_lib_dir = require("assistant_paths").root .. "lib"
local ffi = require("ffi")
local LibHoedown = nil

-- check if hoedown is natively available
-- mostly it's unavailable on KOReader, but available on some other platforms
local ok, _lib = pcall(ffi.loadlib, "hoedown", 3)
if ok then LibHoedown = _lib end

-- check if hoedown is available in the plugin directory
-- in order to use native hoedown, a "lib" directory containing "libhoedown.so.3" and resty-hoedown
-- should be present in the plugin directory, see documents for more details
if not LibHoedown then
    local ok, _lib = pcall(ffi.load, plugin_lib_dir .. "/libhoedown.so.3")
    if ok then LibHoedown = _lib end
end

if LibHoedown then
    -- hook the C binding of hoedown to the resty.hoedown library
    package.preload["resty.hoedown.library"] = function()
        return LibHoedown
    end

    -- load the resty.hoedown library from the plugin's libs directory
    package.path = string.format("%s;%s/?.lua", package.path, plugin_lib_dir)
    local ok, hoedownMD = pcall(require, "resty.hoedown")
    if ok then
        Parser = function (text)
            return hoedownMD(text, {
                rendered    = "html",
                nesting     = 1,
                extensions  = {
                    "space_headers", "tables", "fenced_code", "footnotes", "autolink", "strikethrough",
                    "underline", "highlight", "quote", "superscript", "math", "math_explicit",
                },
            })
        end
        logger.info("Using hoedown (C binding) for markdown parsing")
    end
end

-- fallback to pure Lua implementation
if not Parser then
    Parser = require("apps/filemanager/lib/md")
    logger.info("Using markdown.lua (pure Lua) for markdown parsing")
end

return Parser
