-- Packaged resources are read-only; configuration belongs to the active profile.
local DataStorage = require("datastorage")
local source = debug.getinfo(1, "S").source
local root = assert(source:match("^@(.*/)[^/]+$"), "Cannot locate assistant resources")
return {
    root = root,
    configuration = DataStorage:getSettingsDir() .. "/assistant-configuration.lua",
}
