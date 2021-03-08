package.loaded.socket = nil
package.loaded.FTPCC = nil
local usedPorts = {}
local portProvider = function(num)
    if num == nil then
        if usedPorts[2101] == nil then
            usedPorts[2101] = true
            return 2101
        else return nil end
    else usedPorts[num] = nil end
end
require("FTPCC").server(peripheral.find("modem"), 2100, nil, fs, portProvider, "127.0.0.1"):listen()
