package.loaded.socket = nil
package.loaded.FTPCC = nil

local users = {
    test = "sample"
}

local function authorize(username, password)
    if username == nil or password == nil then return false end
    return users[username] == password
end

require("FTPCC").server(peripheral.find("modem"), 21, authorize):listen()
