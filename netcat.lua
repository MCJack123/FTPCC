local connect, listen
do
  local _obj_0 = require("socket")
  connect, listen = _obj_0.connect, _obj_0.listen
end
local modem = peripheral.find("modem")
if modem == nil then
  error("Modem not found")
end
local args = {
  ...
}
if #args < 2 then
  error("Usage: netcat <id|-l> <port>")
end
local socket
if args[1] == "-l" then
  socket = listen(os.computerID(), modem, tonumber(args[2]))
else
  socket = connect(os.computerID(), modem, tonumber(args[1]), tonumber(args[2]))
end
if socket == nil then
  error("Could not connect to server")
end
print("Connected.")
local ok, err = pcall(function()
  return parallel.waitForAny((function()
    while true do
      local o, e = socket:send(read())
      if not o then
        printError("s: " .. e)
        return 
      end
      if not (socket.is_open) then
        return 
      end
    end
  end), (function()
    while true do
      local d, e = socket:receive(0)
      if d == nil then
        printError("r: " .. e)
        return 
      end
      print(d)
      if not (socket.is_open) then
        return 
      end
    end
  end))
end)
if not ok then
  printError(err)
end
if socket.is_open then
  socket:close()
  return print("Socket closed.")
end
