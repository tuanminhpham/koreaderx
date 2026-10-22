-- LuaSec verifies certificate chains only when requested explicitly and does not
-- check hostnames. Keep both checks local to assistant requests, before HTTP can
-- send credentials or text. Other KOReader users of ssl.https are unaffected.
local https = require("ssl.https")
local url = require("socket.url")
local Paths = require("assistant_paths")

local Transport = {
    cafile = Paths.root .. "../../data/ca-bundle.crt",
}

local function dnsName(name)
    if type(name) ~= "string" or name:find("[^%w%.%-]") then return nil end
    name = name:lower():gsub("%.$", "")
    if name == "" or name:find("..", 1, true) then return nil end
    return name
end

-- LuaSec 1.3.2 exposes SANs through extensions(), but no X509_check_host API.
-- Require SANs (no legacy CN fallback), and only a complete leftmost wildcard.
-- IP literals require an IP SAN; equivalent IPv6 spellings fail closed.
function Transport.verifyHostname(cert, host)
    if not cert or type(host) ~= "string" then return false end
    local sans = (cert:extensions() or {})["2.5.29.17"] or {}
    if host:find(":", 1, true) or host:match("^[%d%.]+$") then
        for _, ip in ipairs(sans.iPAddress or {}) do
            if host:lower() == ip:lower() then return true end
        end
        return false
    end
    host = dnsName(host)
    if not host then return false end
    for _, name in ipairs(sans.dNSName or {}) do
        if dnsName(name) == host then return true end
        if name:sub(1, 2) == "*." then
            local suffix = dnsName(name:sub(3))
            if suffix and suffix:find(".", 1, true)
                    and host:match("^[^.]+%.(.+)$") == suffix then
                return true
            end
        end
    end
    return false
end

function Transport.secure(request)
    if request.url:sub(1, 8):lower() ~= "https://" then return request end
    -- A redirect must never forward a provider's credentials to another origin.
    request.redirect = false
    local target_host = (url.parse(request.url) or {}).host
    local create = https.tcp{
        verify = "peer",
        cafile = Transport.cafile,
        options = {"all", "no_sslv2", "no_sslv3", "no_tlsv1", "no_tlsv1_1"},
    }
    request.create = function()
        local conn = create()
        local connect = conn.connect
        -- LuaSec registers close() only after a successful handshake. Provide it
        -- early as LuaSocket also closes a connection after a failed handshake.
        function conn:close() return self.sock:close() end
        function conn:connect(host, port)
            local ok, result = pcall(connect, self, host, port)
            if not ok then
                self:close()
                local reason = type(result) == "table" and result[1] or result
                return nil, "TLS handshake failed: " .. tostring(reason)
            end
            local checked, matches = pcall(Transport.verifyHostname,
                self.sock:getpeercertificate(), target_host)
            if not checked or not matches then
                self:close()
                return nil, "TLS certificate hostname mismatch"
            end
            return result
        end
        return conn
    end
    return request
end

return Transport
