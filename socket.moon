crc32 = require "crc32"
padstr = (str, size) -> return if #str < size then str .. (" ")\rep size-str else str\sub 1, size

-- message types: connect, connected, message, received, disconnected

if false
    return {
        connect: (me, modem, id, port) -> 
            w = http.websocket("ws://localhost:" .. port)
            return setmetatable {
                send: (s) => w.send(s) or true
                receive: => w.receive!
                close: => w.close!
            }, {__index: (t) => if t == "is_open" then return w.isOpen()}
    }

class socket
    --- Internal contructor; not exported.
    new: (me, modem, id, port, timeout) =>
        @me = me
        @modem = modem
        @id = id
        @port = port
        @timeout = timeout
        @is_open = true
        @message_queue = {}
    
    --- Send a string of data.
    -- @param data *string* The data to send.
    -- @return *boolean* Whether the transmission succeeded.
    -- @return *string/nil* If it failed, a reason for failure if available.
    send: (data) =>
        if data != nil and type(data) != "string" then error "bad argument #1 (expected string, got " .. type(data) .. ")", 2
        return false unless @is_open
        @modem.open @port if not @is_open
        tm = if @timeout == 0 then nil else os.startTimer @timeout
        @modem.transmit @port, @port, {from: @me, to: @id, type: "message", size: #data, :data}
        while true
            @modem.open @port if not @is_open
            ev = {os.pullEvent!}
            if ev[1] == "timer" and ev[2] == tm then return false, "Timeout"
            elseif ev[1] == "modem_message" and ev[3] == @port and ev[4] == @port and (type(ev[5]) == "table")
                if ev[5].to = @me and ev[5].from == @id -- weird bug requiring this on a new line...?
                    switch ev[5].type
                        when "received"
                            os.cancelTimer tm if @timeout > 0
                            return tonumber(padstr(ev[5].data, ev[5].size)) == crc32(data), "Invalid checksum"
                        when "disconnected"
                            @close!
                            os.cancelTimer tm if @timeout > 0
                            return false, (ev[5].size > 0 and padstr ev[5].data, ev[5].size or "Socket closed")
    
    --- Receive a string of data.
    -- @param timeout *number/nil* An optional extra timeout option to override the initial timeout set in connect() or listen().
    -- @return *string/nil* The data received, or nil on error.
    -- @return *string/nil* If an error occurred, a reason if available.
    receive: (timeout=@timeout) =>
        return nil, "Socket closed" unless @is_open
        if type(timeout) != "number" then error "bad argument #1 (expected number, got " .. type(timeout) .. ")", 2
        @modem.open @port if not @is_open
        tm = if timeout == 0 then nil else os.startTimer timeout
        while true
            @modem.open @port if not @is_open
            ev = {os.pullEvent!}
            unless @is_open
                os.cancelTimer tm if timeout > 0
                return nil, "Socket closed"
            if ev[1] == "timer" and ev[2] == tm then return nil, "Timeout"
            elseif ev[1] == "modem_message" and ev[3] == @port and ev[4] == @port and type(ev[5]) == "table"
                if ev[5].to = @me and ev[5].from == @id then
                    switch ev[5].type
                        when "message"
                            @modem.transmit @port, @port, {from: @me, to: @id, type: "received", size: 8, data: ("%08X")\format crc32 padstr ev[5].data, ev[5].size}
                            os.cancelTimer tm if timeout > 0
                            return padstr ev[5].data, ev[5].size
                        when "disconnected"
                            @close!
                            os.cancelTimer tm if timeout > 0
                            return nil, if ev[5].size > 0 then padstr ev[5].data, ev[5].size else "Socket closed"
    
    --- Closes the socket.
    -- @param reason *string/nil* An optional reason to provide to the other party.
    close: (reason) =>
        if reason != nil and type(reason) != "string" then error "bad argument #1 (expected string, got " .. type(reason) .. ")", 2
        return unless @is_open
        @modem.transmit @port, @port, {from: @me, to: @id, type: "disconnected", size: if reason then #reason else 0, data: reason or ""}
        @modem.close @port
        @is_open = false

--- Connect to an open socket listener on another computer.
-- @param me *any* A unique identifier for this computer (can theoretically be any value).
-- @param modem *modem* The modem peripheral object to use.
-- @param id *any* The unique identifier of the computer to connect to.
-- @param port *number* The port to connect to (0-65535).
-- @param timeout *number/nil* The number of seconds to wait for a response from the other party (default is 5).
-- @return *socket/nil* A socket object, or nil on error.
-- @return *string/nil* On error, a string describing the error (if available).
connect = (me, modem, id, port, timeout=5) ->
    if type(modem) != "table" then error "bad argument #2 (expected modem (table), got " .. type(modem) .. ")", 2
    elseif type(modem.open) != "function" or type(modem.transmit) != "function" or type(modem.close) != "function" then error "bad argument #2 (expected modem, got non-modem table)", 2
    if type(port) != "number" then error "bad argument #4 (expected number, got " .. type(port) .. ")", 2
    elseif port < 0 or port > 65535 then error "bad argument #4 (port out of range: " .. port .. ")", 2
    if type(timeout) != "number" then error "bad argument #5 (expected number, got " .. type(timeout) .. ")", 2
    if me == id then error "attempted to connect to self", 2
    modem.open port
    modem.transmit port, port, {from: me, to: id, type: "connect", size: 0, data: ""}
    tm = os.startTimer timeout
    while true
        ev = {os.pullEvent!}
        if ev[1] == "timer" and ev[2] == tm
            modem.close port
            return nil, "Timeout"
        elseif ev[1] == "modem_message" and ev[3] == port and ev[4] == port and type(ev[5]) == "table" and ev[5].from == id and ev[5].to == me
            if ev[5].type == "connected"
                return socket me, modem, id, port, timeout
            elseif ev[5].type == "disconnected" or ev[5].type == "error"
                modem.close port
                return nil, padstr ev[5].data, ev[5].size

--- Listen for incoming connections on a port.
-- @param me *any* A unique identifier for this computer (can theoretically be any value).
-- @param modem *modem* The modem peripheral object to use.
-- @param port *number* The port to listen on (0-65535).
-- @param timeout *number/nil* The number of seconds to wait for a response from the other party (default is 5).
-- @return *socket/nil* A socket object.
listen = (me, modem, port, timeout=5) ->
    if type(modem) != "table" then error "bad argument #2 (expected modem (table), got " .. type(modem) .. ")", 2
    elseif type(modem.open) != "function" or type(modem.transmit) != "function" or type(modem.close) != "function" then error "bad argument #2 (expected modem, got non-modem table)", 2
    if type(port) != "number" then error "bad argument #3 (expected number, got " .. type(port) .. ")", 2
    elseif port < 0 or port > 65535 then error "bad argument #3 (port out of range: " .. port .. ")", 2
    if type(timeout) != "number" then error "bad argument #4 (expected number, got " .. type(timeout) .. ")", 2
    modem.open port
    while true
        ev = {os.pullEvent "modem_message"}
        if ev[3] == port and ev[4] == port and type(ev[5]) == "table" and ev[5].to == me and ev[5].type == "connect"
            modem.transmit port, port, {from: me, to: ev[5].from, type: "connected", size: 0, data: ""}
            return socket me, modem, ev[5].from, port, timeout

return {connect:connect, listen:listen}