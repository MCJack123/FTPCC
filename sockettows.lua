local socket = require "socket"
local modem = peripheral.find "modem"
local localID, localPort, remotePort, persist = ...
if not remotePort then error("Usage: sockettows <computer ID|'listen'> <computer port> <WebSocket port>") end
local sock, ws, err
ws, err = http.websocket("ws://127.0.0.1:" .. remotePort)
if not ws then error("Could not connect to WebSocket: " .. err) end
if localID == "listen" then
    print("Listening on computer port " .. localPort)
    sock, err = socket.listen(os.computerID(), modem, tonumber(localPort))
else
    print("Connecting to computer " .. localID .. " port " .. localPort)
    if persist then
        for i = 1, 600 do
            sock, err = socket.connect(os.computerID(), modem, tonumber(localID), tonumber(localPort), 0.1)
            if sock then break end
        end
    else sock, err = socket.connect(os.computerID(), modem, tonumber(localID), tonumber(localPort)) end
end
if not sock then ws.close() error("Could not connect to socket: " .. err) end
local trapped = {}
--parallel.waitForAny(function() --[[ws, err = http.websocket("ws://127.0.0.1:" .. remotePort)]] sleep(2) end, function() while sock.is_open do trapped[#trapped+1] = sock:receive() end end)
print("Connected to computer " .. sock.id .. " port " .. localPort .. " <=> WebSocket port " .. remotePort)
pcall(parallel.waitForAny, function()
    while sock.is_open and ws.isOpen() do
        local d = ws.receive()
        if d then print("<", (d:gsub("%s+$", ""))) sock:send(d) end
    end
end, function()
    while ws.isOpen() and sock.is_open do
        local d = #trapped > 0 and table.remove(trapped, 1) or sock:receive()
        if d and d:find("^227 ") then sleep(2) end
        if d then print(">", (d:gsub("%s+$", ""))) ws.send(d) end
    end
end)
if ws.isOpen() then ws.close() assert(not ws.isOpen()) else print("Socket closed by WebSocket host") end
if sock.is_open then sock:close() else print("Socket closed by remote host") end