if fs.mount == nil then error("Requires remount") end
local FTPCC = require "FTPCC"
local client = FTPCC.client(peripheral.find("modem"), 1)
write "Username: "
local user = read()
write "Password: "
local pass = read("\x07")
local ok, err = client:login(user, pass)
if not ok then error(err) end
local unself = function(obj) return setmetatable({}, {__index = function(self, idx) if type(obj[idx]) == "function" then return function(...) return obj[idx](obj, ...) end else return obj[idx] end end}) end
local ftpobj = unself(client)
fs.mount("ftpshare", ftpobj)
