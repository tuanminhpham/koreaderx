#!/usr/bin/env python3
"""Exercise assistant TLS over loopback only; no keys, profile or external APIs.

Requires Python 3, openssl, and a KOReader host runtime containing LuaJIT/LuaSec.
Example: python3 tools/koreaderx/test-assistant-tls.py --runtime /path/to/host
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading

LUA = r'''
local plugin, ca, valid, wrong, untrusted, missing = unpack(arg)
package.path = plugin .. "/?.lua;" .. package.path
package.preload.assistant_paths = function() return {root=plugin .. "/"} end
package.preload.logger = function() return {warn=function() end} end
package.preload.device = function() return {} end
package.preload["ui/trapper"] = function() return {} end
package.preload.socketutil = function()
    return {set_timeout=function()
        require("socket.http").TIMEOUT=3; require("ssl.https").TIMEOUT=3
    end, reset_timeout=function() end, table_sink=require("ltn12").sink.table}
end
local chunks = {}
package.preload["ffi/util"] = function()
    return {writeToFD=function(_, text) chunks[#chunks+1]=text end}
end
local ffi = require("ffi")
ffi.cdef[[int dup(int oldfd); int close(int fd);]]
local Transport = require("assistant_transport")
local Base = require("api_handlers.base")
local https = require("ssl.https")
local original_verify, original_tcp = https.cert_verify, https.tcp
local function cert(dns, ip)
    return {extensions=function() return {["2.5.29.17"]={dNSName=dns, iPAddress=ip}} end}
end
local san_cases = {
    {cert({"API.example.com"}), "api.example.com", true},
    {cert({"*.example.com"}), "api.example.com", true},
    {cert({"*.example.com"}), "example.com", false},
    {cert({"*.example.com"}), "a.b.example.com", false},
    {cert({"*.com"}), "example.com", false},
    {cert({"api*.example.com"}), "api1.example.com", false},
    {cert({"api.example.com\0.attacker"}), "api.example.com", false},
    {cert({"api.example.com"}), "api.example.com.attacker", false},
    {cert({"127.0.0.1"}), "127.0.0.1", false},
    {cert({}, {"127.0.0.1"}), "127.0.0.1", true},
    {cert({}, {"::1"}), "::1", true},
    {cert({}, {"::1"}), "::2", false},
    {cert({}), "api.example.com", false},
}
for i, case in ipairs(san_cases) do
    assert(Transport.verifyHostname(case[1], case[2]) == case[3], "SAN case " .. i)
end
assert(Transport.secure{url="http://127.0.0.1/"}.create == nil)
local cases = {
    {"valid_dns", valid, ca, true},
    {"valid_ip", valid:gsub("localhost", "127.0.0.1"), ca, true},
    {"wrong_hostname", wrong, ca, false},
    {"untrusted_ca", untrusted, ca, false},
    {"missing_ca", valid, missing, false},
}
local body = "local-fixture-no-user-data"
local headers = {["content-length"]=#body, ["content-type"]="text/plain",
    Authorization="Bearer local-fixture-not-a-credential"}
for _, case in ipairs(cases) do
    Transport.cafile = case[3]
    for _, mode in ipairs({"nonstream", "stream"}) do
        if mode == "nonstream" then
            local success, status, content = Base:makeRequest(case[2], headers, body, 3, 3)
            if case[4] then
                assert(success and status == 200 and content == "fixture-ok", case[1] .. " nonstream")
            else
                assert(not success and status == Base.CODE_NETWORK_ERROR, case[1] .. " must reject")
                assert(content:find("TLS", 1, true), case[1] .. " TLS rejection")
            end
        else
            chunks = {}
            local fd = ffi.C.dup(1)
            assert(fd >= 0)
            Base:backgroudRequest(case[2], headers, body)(1, fd)
            local content = table.concat(chunks)
            if case[4] then
                assert(content == "fixture-ok", case[1] .. " stream")
            else
                assert(content:find(Base.PROTOCAL_NON_200, 1, true), case[1] .. " stream must reject")
                assert(content:find("TLS", 1, true), case[1] .. " stream TLS rejection")
            end
        end
        print("PASS " .. case[1] .. " " .. mode)
    end
end
assert(https.cert_verify == original_verify and https.tcp == original_tcp, "global HTTPS state changed")
local redirect = Transport.secure{url=valid}
assert(redirect.redirect == false, "credentialed HTTPS redirects must be disabled")
print("PASS SAN " .. #san_cases .. "; HTTPS globals unchanged; redirects disabled")
'''


def openssl(directory, *args):
    subprocess.run(["openssl", *args], cwd=directory, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make_ca(directory, name):
    openssl(directory, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
            "-days", "1", "-subj", "/CN=" + name, "-keyout", name + ".key",
            "-out", name + ".crt", "-addext", "basicConstraints=critical,CA:TRUE")


def make_leaf(directory, name, ca, san):
    openssl(directory, "req", "-new", "-newkey", "rsa:2048", "-nodes",
            "-subj", "/CN=unused.invalid", "-keyout", name + ".key", "-out", name + ".csr")
    (directory / (name + ".ext")).write_text(
        "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n"
        "extendedKeyUsage=serverAuth\nsubjectAltName=" + san + "\n")
    openssl(directory, "x509", "-req", "-in", name + ".csr", "-CA", ca + ".crt",
            "-CAkey", ca + ".key", "-CAcreateserial", "-days", "1", "-sha256",
            "-extfile", name + ".ext", "-out", name + ".crt")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if body != b"local-fixture-no-user-data":
            raise AssertionError("unexpected fixture body")
        self.server.requests_received += 1
        self.send_response(200)
        self.send_header("Content-Length", "10")
        self.end_headers()
        self.wfile.write(b"fixture-ok")

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--plugin", type=Path,
                        default=Path(__file__).resolve().parent.parent.parent / "plugins/assistant.koplugin")
    args = parser.parse_args()
    runtime, plugin = args.runtime.resolve(), args.plugin.resolve()
    with tempfile.TemporaryDirectory(prefix="assistant-local-tls-") as temp:
        directory = Path(temp)
        make_ca(directory, "trusted")
        make_ca(directory, "untrusted")
        make_leaf(directory, "valid", "trusted", "DNS:localhost,IP:127.0.0.1")
        make_leaf(directory, "wrong", "trusted", "DNS:wrong.invalid")
        make_leaf(directory, "unknown", "untrusted", "DNS:localhost,IP:127.0.0.1")
        servers = []
        try:
            for name in ("valid", "wrong", "unknown"):
                server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
                server.requests_received = 0
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(directory / (name + ".crt"), directory / (name + ".key"))
                server.socket = context.wrap_socket(server.socket, server_side=True)
                threading.Thread(target=server.serve_forever, daemon=True).start()
                servers.append(server)
            script = directory / "exercise.lua"
            script.write_text(LUA)
            env = os.environ.copy()
            env["LUA_PATH"] = "common/?.lua;frontend/?.lua;?.lua"
            env["LUA_CPATH"] = "common/?.so;?.so"
            result = subprocess.run([str(runtime / "luajit"), str(script), str(plugin),
                str(directory / "trusted.crt"),
                *["https://localhost:%d/" % s.server_port for s in servers],
                str(directory / "missing.crt")], cwd=runtime, env=env,
                capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            counts = [s.requests_received for s in servers]
            assert counts == [4, 0, 0], counts
            print(json.dumps({"status": "PASS", "scope": "loopback TLS only",
                "request_cases": 10, "san_cases": 13,
                "valid_server_received": counts[0],
                "wrong_hostname_received": counts[1],
                "untrusted_server_received": counts[2],
                "https_global_state_unchanged": True, "https_redirects_disabled": True,
                "output": result.stdout.splitlines()}, indent=2))
        finally:
            for server in servers:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    main()
