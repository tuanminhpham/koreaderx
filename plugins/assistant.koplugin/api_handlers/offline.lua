-- Local setup mode: deliberately performs no request or simulated AI answer.
local Handler = require("api_handlers.base"):new()
function Handler:query()
    return nil, "No AI service is configured. Set up assistant-configuration.lua in the active profile settings directory and restart KOReader. No request was sent."
end
return Handler
