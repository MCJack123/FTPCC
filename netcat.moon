import connect, listen from require "socket"

modem = peripheral.find "modem"
error "Modem not found" if modem == nil
args = {...}
error "Usage: netcat <id|-l> <port>" if #args < 2

local socket
if args[1] == "-l" then socket = listen os.computerID!, modem, tonumber(args[2])
else socket = connect os.computerID!, modem, tonumber(args[1]), tonumber(args[2])
if socket == nil then error "Could not connect to server"
print "Connected."
ok, err = pcall -> parallel.waitForAny (-> 
        while true 
            o, e = socket\send read!
            if not o
                printError "s: " .. e
                return
            return unless socket.is_open
    ), (-> 
        while true 
            d, e = socket\receive 0
            if d == nil
                printError "r: " .. e
                return
            print d
            return unless socket.is_open
    )
if not ok then printError err
if socket.is_open
    socket\close!
    print "Socket closed."