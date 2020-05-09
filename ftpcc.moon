-- FTPCC - FTP client/server for ComputerCraft over modem API
-- By JackMacWindows
--
-- This implementation complies with RFC 959 as close as possible. Theoretically,
-- this code could be ported to work with real FTP servers over a WebSocket (or 
-- TCP connection if possible) to transfer real files.

import connect, listen from require "socket"

padstr = (str, size) -> if #str < size then str .. (" ")\rep size-str else str\sub 1, size

-- Creates a port provider function.
createPortProvider = (modem) ->
    usedPorts = {}
    return (num) ->
        if num == nil
            if usedPorts[20] == nil
                usedPorts[20] = true
                return 20
            else
                i = 5000
                while i < 65536 and usedPorts[i] and modem.isOpen i do i+=1
                return if i > 65535 then nil else i
        else usedPorts[num] = nil

class client
    --- Creates a new FTP client.
    -- @param modem *modem* The modem object to use
    -- @param id *number* The ID of the computer to connect to
    -- @param port *number/nil* The port to connect to (defaults to 21)
    -- @param pasv *function/boolean/nil* Specifies whether to use a passive connection. In active mode, this parameter must be a function that takes either nil (requests a port) or a number (frees a previously requested port). In passive mode, this parameter must be false. Defaults to passive mode.
    -- @param timeout *number/nil* Timeout for socket operations (defaults to 5)
    new: (modem, id, port=21, pasv=false, timeout=5) =>
        @modem = modem
        @timeout = timeout
        @connection, err = connect os.computerID!, modem, id, port, timeout
        if @connection == nil then error "Could not connect to server: " .. (err or ""), 2
        @pasv = pasv
        @transfer_params = {type: "A", mode: "S"}
        @_send_command!

    -- Sends a command and handles the reply
    _send_command: (command) =>
        return false, 421, "Connection closed" if not @connection.is_open
        if command != nil
            ok, err = @connection\send command
            if not ok then error "Could not send command: " .. err, 2
        res, err = @connection\receive!
        if res == nil then error "Could not receive reply: " .. err, 2
        code = res\sub 1, 3
        if tonumber(code) == nil then error "Malformed reply (invalid code): " .. res
        reply = ""
        if res\sub(4, 4) == '-'
            for line in res\sub(5)\gmatch "[^\n]+"
                if line\sub(1, 4) == code .. " "
                    reply ..= line\sub 5
                    break
                else reply ..= line .. "\n"
        elseif res\sub(4, 4) == ' ' then reply = res\sub 5
        else error "Malformed reply (invalid code separator):" .. res
        switch math.floor tonumber(code) / 100
            when 1 then return @_send_command!
            when 2, 3 then return true, tonumber(code), reply
            when 4, 5 then return false, tonumber(code), reply
            else error "Malformed reply (invalid code): " .. code

    -- Sends a command that will receive data over the data port
    _receive_data: (command) =>
        if @pasv
            port = @pasv!
            if port == nil then error "Ran out of ports for data connection"
            id = os.computerID!
            ok, code, res = @_send_command "PORT " .. math.floor(id / 16777216) .. "," .. (math.floor(id / 65536) % 256) .. "," .. (math.floor(id / 256) % 256) .. "," .. (id % 256) .. "," .. math.floor(port / 256) .. "," .. (id % 256)
            return nil, code, res if code != 200
            local data, data_connection, err
            parallel.waitForAll (->
                    ok, code, err = @_send_command command
                    if not ok
                        data_connection\close!
                        os.queueEvent "socket_close_aaaaaaaaaaa" -- needed some sort of event name
                ), (-> 
                    data_connection = listen os.computerID!, @modem, port, @timeout
                    while data_connection.is_open
                        d = data_connection\receive!
                        break if d == nil
                        switch @transfer_params.mode
                            when "S" then data = (data or "") .. d
                            when "B"
                                descriptor = d\byte 1
                                size = d\byte(2) * 256 + d\byte(3)
                                data = (data or "") .. padstr d, size
                                if math.floor(descriptor / 128) == 1
                                    data_connection\close!
                                    break
                            when "C"
                                b = d\byte 1
                                if b == 0 and math.floor(d\byte(2) / 128) == 1 
                                    data_connection\close!
                                    break
                                elseif math.floor(b / 128) == 0 then data = (data or "") .. d\sub(2, (b%128)+1)
                                elseif math.floor(b / 64) % 2 == 0 then data = (data or "") .. d\sub(2, 2)\rep(b % 64)
                                else
                                    if @transfer_params.type == "A" or @transfer_params.type == "E" then data = (data or "") .. (" ")\rep(b % 64)
                                    elseif @transfer_params.type == "I" or @transfer_params.type == "L" then data = (data or "") .. ("\0")\rep(b % 64)
                )
            data_connection\close! if data_connection.is_open
            @pasv port
            if @transfer_params.type == "A" and data != nil then data = data\gsub "[\128-\255]", "?"
            return data, code, err
        else
            ok, code, res = @_send_command "PASV"
            return false, code, res if code != 227
            i1, i2, i3, i4, p1, p2 = res\match ("(%d+),")\rep(5) .. "(%d+)"
            id = tonumber(i1)*16777216 + tonumber(i2)*65536 + tonumber(i3)*255 + tonumber(i4)
            port = tonumber(p1)*256 + tonumber(p2)
            data_connection = connect os.computerID!, @modem, id, port, @timeout
            if data_connection == nil then return false, 0, "Could not connect to server"
            local data, err
            parallel.waitForAll (->
                    ok, code, err = @_send_command command
                    if not ok
                        data_connection\close!
                        os.queueEvent "socket_close_aaaaaaaaaaa"
                ), (->
                    while data_connection.is_open
                        d = data_connection\receive!
                        break if d == nil
                        switch @transfer_params.mode
                            when "S" then data = (data or "") .. d
                            when "B"
                                descriptor = d\byte 1
                                size = d\byte(2) * 256 + d\byte(3)
                                data = (data or "") .. padstr d, size
                                if math.floor(descriptor / 128) == 1
                                    data_connection\close!
                                    break
                            when "C"
                                b = d\byte 1
                                if b == 0 and math.floor(d\byte(2) / 128) == 1 
                                    data_connection\close!
                                    break
                                elseif math.floor(b / 128) == 0 then data = (data or "") .. d\sub(2, (b%128)+1)
                                elseif math.floor(b / 64) % 2 == 0 then data = (data or "") .. d\sub(2, 2)\rep(b % 64)
                                else
                                    if @transfer_params.type == "A" or @transfer_params.type == "E" then data = (data or "") .. (" ")\rep(b % 64)
                                    elseif @transfer_params.type == "I" or @transfer_params.type == "L" then data = (data or "") .. ("\0")\rep(b % 64)
                )
            data_connection\close! if data_connection.is_open
            if @transfer_params.type == "A" then data = data\gsub "[\128-\255]", "?"
            return data, code, err

    -- Sends a command that will send data over the data port
    _send_data: (command, data) =>
        if @transfer_params.type == "A" then data = data\gsub "[\128-\255]", "?"
        if @pasv
            port = @pasv!
            if port == nil then error "Ran out of ports for data connection"
            id = os.computerID!
            ok, code, res = @_send_command "PORT " .. math.floor(id / 16777216) .. "," .. (math.floor(id / 65536) % 256) .. "," .. (math.floor(id / 256) % 256) .. "," .. (id % 256) .. "," .. math.floor(port / 256) .. "," .. (id % 256)
            return false, code, res if code != 200
            local data_connection, err
            parallel.waitForAny (->
                    ok, code, err = @_send_command command
                    if ok then while data_connection.is_open do os.pullEvent!
                ), (-> 
                    data_connection = listen os.computerID!, @modem, port, @timeout
                    return unless data_connection.is_open
                    switch @transfer_params.mode
                        when "S" then for i = 1, #data, 65536 do data_connection\send data\sub i, i + 65535
                        when "B"
                            for i = 1, #data, 65535
                                d = data\sub i, i + 65534
                                data_connection\send (if #d < 65535 then "\0" else "\128") .. string.char(#d / 256) .. string.char(#d % 256) .. d
                        when "C"
                            for i = 1, #data, 127
                                d = data\sub i, i + 126
                                data_connection\send string.char(#d) .. d
                            data_connection\send "\0\128"
                    data_connection\close!
                )
            @pasv port
            return ok, code, err
        else
            ok, code, res = @_send_command "PASV"
            return false, code, res if code != 227
            i1, i2, i3, i4, p1, p2 = res\match ("(%d+),")\rep(5) .. "(%d+)"
            id = tonumber(i1)*16777216 + tonumber(i2)*65536 + tonumber(i3)*255 + tonumber(i4)
            port = tonumber(p1)*256 + tonumber(p2)
            data_connection = connect os.computerID!, @modem, id, port, @timeout
            if data_connection == nil then return false, 0, "Could not connect to server"
            ok, code, err = @_send_command command
            if not ok
                data_connection\close!
                return ok, code, err
            switch @transfer_params.mode
                when "S" then for i = 1, #data, 65536 do data_connection\send data\sub i, i + 65535
                when "B"
                    for i = 1, #data, 65535
                        d = data\sub i, i + 65534
                        data_connection\send (if #d < 65535 then "\0" else "\128") .. string.char(#d / 256) .. string.char(#d % 256) .. d
                when "C"
                    for i = 1, #data, 127
                        d = data\sub i, i + 126
                        data_connection\send string.char(#d) .. d
                    data_connection\send "\0\128"
            data_connection\close!
            return true

    --- Log into the server.
    -- @param username *string* The username to log in as
    -- @param password *string/nil* The password for the user (if desired)
    -- @return *boolean* Whether the login succeeded
    -- @return *string/nil* On error, a message describing the error sent by the server
    login: (username, password) =>
        if type(username) != "string" then error "bad argument #1 (expected string, got " .. type(username) .. ")", 2
        if password != nil and type(password) != "string" then error "bad argument #2 (expected string, got " .. type(password) .. ")", 2
        ok, code, err = @_send_command "USER " .. username
        switch code
            when 230 then return true
            when 500, 501, 421, 530 then return false, err
            when 331, 332
                if password == nil then return false, "Password required"
            else error "Malformed reply (invalid code): " .. code
        ok, code, err = @_send_command "PASS " .. password
        switch code
            when 230 then return true
            when 202 then return true -- is this correct?
            when 500, 502, 421, 530 then return false, err
            when 332 then return false, err
            else error "Malformed reply (invalid code): " .. code

    --- Close the connection to the server.
    close: =>
        @_send_command "QUIT"
        @connection\close!

    --- Sets type & mode of transfer for FTP.
    -- @param dtype *string/nil* Data type: "A" = ASCII (text), "I" = Image (binary)
    -- @param mode *string/nil* Mode for data transmission: "S" = stream, "B" = block, "C" = compressed
    -- @return The current data type (may not be the same as requested if an error occurred)
    -- @return The current transmission mode (may not be the same as requested if an error occurred)
    setTransferParams: (dtype=@transfer_params.type, mode=@transfer_params.mode) =>
        if type(dtype) != "string" then error "bad argument #1 (expected string, got " .. type(dtype) .. ")", 2
        if type(mode) != "string" then error "bad argument #2 (expected string, got " .. type(mode) .. ")", 2
        if dtype != "A" and dtype != "I" then error "bad argument #1 (invalid data type)", 2
        if mode != "S" and mode != "B" and mode != "C" then error "bad argument #2 (invalid transmission mode)", 2
        if dtype != @transfer_params.type
            ok, code, err = @_send_command "TYPE " .. dtype
            @transfer_params.type = dtype if code == 200
        if mode != @transfer_params.mode
            ok, code, err = @_send_command "MODE " .. mode
            @transfer_params.mode = mode if code == 200
        return @transfer_params.type, @transfer_params.mode
    
    -- The following functions are overrides for the FS API.

    list: (path) =>
        if type(path) != "string" then error "bad argument #1 (expected string, got " .. type(path) .. ")", 2
        path = "/" if path == ""
        local o
        if @transfer_params.type != "A"
            o = @transfer_params.type
            if @setTransferParams("A") != "A" then error "Could not switch to ASCII data type"
        data, code, err = @_receive_data "NLST " .. path
        if o then @setTransferParams o
        if not data then error err .. " (" .. code .. ")", 2
        return [line for line in data\gmatch "[^\r\n]+"]
    
    exists: (path) => #[v for _,v in ipairs @list fs.getDir path when v == fs.getName path] > 0

    isDir: (path) =>
        if type(path) != "string" then error "bad argument #1 (expected string, got " .. type(path) .. ")", 2
        path = "/" if path == ""
        -- checks by trying to cd into path
        ok, code, err = @_send_command "CWD " .. path
        switch code
            when 533, 550 then return false
            when 200, 250
                @_send_command "CWD /"
                return true
            else error err .. " (" .. code .. ")", 2

    isReadOnly: => false -- no easy way to determine this information

    getSize: (path) =>
        if type(path) != "string" then error "bad argument #1 (expected string, got " .. type(path) .. ")", 2
        path = "/" if path == ""
        -- Gets file size by reading entire file; this is expensive
        data, code, err = @_receive_data "RETR " .. path
        if data == nil then error err .. " (" .. code .. ")", 2
        return #data

    getFreeSpace: => 1000000 -- no standard way to find this

    makeDir: (path) =>
        if type(path) != "string" then error "bad argument #1 (expected string, got " .. type(path) .. ")", 2
        ok, code, err = @_send_command "MKD " .. path
        if not ok then error err .. " (" .. code .. ")", 2
    
    move: (fromPath, toPath) =>
        if type(fromPath) != "string" then error "bad argument #1 (expected string, got " .. type(fromPath) .. ")", 2
        if type(toPath) != "string" then error "bad argument #2 (expected string, got " .. type(toPath) .. ")", 2
        ok, code, err = @_send_command "RNFR " .. fromPath
        if not ok then error err .. " (" .. code .. ")", 2
        ok, code, err = @_send_command "RNTO " .. toPath
        if not ok then error err .. " (" .. code .. ")", 2
    
    copy: (fromPath, toPath) =>
        if type(fromPath) != "string" then error "bad argument #1 (expected string, got " .. type(fromPath) .. ")", 2
        if type(toPath) != "string" then error "bad argument #2 (expected string, got " .. type(toPath) .. ")", 2
        -- copying involves two transfers of the entire file, this is expensive
        local o
        if @transfer_params.type != "I"
            o = @transfer_params.type
            if @setTransferParams("I") != "I" then error "Could not switch to Image data type"
        data, code, err = @_receive_data "RETR " .. fromPath
        if data == nil
            if o then @setTransferParams o
            error err .. " (" .. code .. ")", 2
        ok, code, err = @_send_data "STOR " .. toPath, data
        if not ok
            if o then @setTransferParams o
            error err .. " (" .. code .. ")", 2

    delete: (path) =>
        if type(path) != "string" then error "bad argument #1 (expected string, got " .. type(path) .. ")", 2
        ok, code, err = @_send_command "DELE " .. path
        if not ok
            ok = @_send_command "RMD " .. path
            if ok then for f in ipairs @list path do @delete fs.combine path, f
            else error err .. " (" .. code .. ")", 2

    open: (path, mode) =>
        if type(path) != "string" then error "bad argument #1 (expected string, got " .. type(path) .. ")", 2
        if type(mode) != "string" then error "bad argument #2 (expected string, got " .. type(mode) .. ")", 2
        switch mode
            when "r"
                if @setTransferParams("A") != "A" then error "Could not switch to ASCII data type"
                data, code, err = @_receive_data "RETR " .. path
                if data == nil then return nil, err .. " (" .. code .. ")"
                offset = 1
                return {
                    close: -> nil
                    readLine: ->
                        return nil if offset >= #data
                        i = data\find("\n", offset) or #data + 1
                        l = data\sub offset, i-1
                        offset = i + 1
                        return l
                    readAll: ->
                        return nil if offset >= #data
                        l = data\sub offset
                        offset = #data
                        return l
                    read: (size) ->
                        return nil if offset >= #data
                        l = data\sub offset, offset + size
                        offset += size
                        return l
                    seek: (whence, pos) ->
                        pos = pos or 0
                        if type(whence) == "number" and type(pos) == nil
                            pos = whence
                            whence = "cur"
                        switch whence
                            when "cur" then offset += math.max math.min(pos, #data), 0
                            when "set" then offset = math.max math.min(pos, #data), 0
                            when "end" then offset = math.max math.min(#data - pos, #data), 0
                        return offset
                }
            when "w"
                data = ""
                offset = 1
                t = {
                    flush: ->
                        if @setTransferParams("A") != "A" then error "Could not switch to ASCII data type"
                        ok, code, err = @_send_data "STOR " .. path, data
                        if not ok then error err .. " (" .. code .. ")"
                    write: (str) ->
                        data = data\sub(1, offset - 1) .. str .. data\sub(offset)
                        offset += #str
                    writeLine: (str) ->
                        data = data\sub(1, offset - 1) .. str .. "\n" .. data\sub(offset)
                        offset += #str + 1
                    seek: (whence, pos) ->
                        pos = pos or 0
                        if type(whence) == "number" and type(pos) == nil
                            pos = whence
                            whence = "cur"
                        switch whence
                            when "cur" then offset += math.max math.min(pos, #data), 0
                            when "set" then offset = math.max math.min(pos, #data), 0
                            when "end" then offset = math.max math.min(#data - pos, #data), 0
                        return offset
                }
                t.close = t.flush
                return t
            when "a"
                data = ""
                offset = 1
                return {
                    close: ->
                        if @setTransferParams("A") != "A" then error "Could not switch to ASCII data type"
                        ok, code, err = @_send_data "STOA " .. path, data
                        if not ok then error err .. " (" .. code .. ")"
                    write: (str) ->
                        data = data\sub(1, offset - 1) .. str .. data\sub(offset)
                        offset += #str
                    writeLine: (str) ->
                        data = data\sub(1, offset - 1) .. str .. "\n" .. data\sub(offset)
                        offset += #str + 1
                    flush: -> nil
                }
            when "rb"
                if @setTransferParams("I") != "I" then error "Could not switch to Image data type"
                data, code, err = @_receive_data "RETR " .. path
                if data == nil then return nil, err .. " (" .. code .. ")"
                offset = 1
                return {
                    close: -> nil
                    readAll: ->
                        return nil if offset >= #data
                        l = data\sub offset
                        offset = #data
                        return l
                    read: (size) ->
                        return nil if offset >= #data
                        if size == nil
                            offset+=1
                            return data\byte offset - 1
                        l = data\sub offset, offset + size
                        offset += size
                        return l
                    seek: (whence, pos) ->
                        pos = pos or 0
                        if type(whence) == "number" and type(pos) == nil
                            pos = whence
                            whence = "cur"
                        switch whence
                            when "cur" then offset += math.max math.min(pos, #data), 0
                            when "set" then offset = math.max math.min(pos, #data), 0
                            when "end" then offset = math.max math.min(#data - pos, #data), 0
                        return offset
                }
            when "wb"
                data = ""
                offset = 1
                t = {
                    flush: ->
                        if @setTransferParams("I") != "I" then error "Could not switch to Image data type"
                        ok, code, err = @_send_data "STOR " .. path, data
                        if not ok then error err .. " (" .. code .. ")"
                    write: (str) ->
                        data = data\sub(1, offset - 1) .. (if type(str) == "number" then string.char str else str) .. data\sub(offset)
                        offset += #str
                    seek: (whence, pos) ->
                        pos = pos or 0
                        if type(whence) == "number" and type(pos) == nil
                            pos = whence
                            whence = "cur"
                        switch whence
                            when "cur" then offset += math.max math.min(pos, #data), 0
                            when "set" then offset = math.max math.min(pos, #data), 0
                            when "end" then offset = math.max math.min(#data - pos, #data), 0
                        return offset
                }
                t.close = t.flush
                return t
            when "ab"
                data = ""
                offset = 1
                return {
                    close: ->
                        if @setTransferParams("I") != "I" then error "Could not switch to Image data type"
                        ok, code, err = @_send_data "STOA " .. path, data
                        if not ok then error err .. " (" .. code .. ")"
                    write: (str) ->
                        data = data\sub(1, offset - 1) .. (if type(str) == "number" then string.char str else str) .. data\sub(offset)
                        offset += #str
                    flush: -> nil
                }
            else return nil, "Unknown mode \"" .. mode .. '"'

    find: => nil -- unimplemented

class server_connection
    new: (socket) =>
        @socket = socket
        @dir = ""
        @transfer_params = {type: "A", mode: "S"}
        @status = {
            total_bytes: 0
            current_bytes: nil
            target_bytes: nil
            current_command: nil
        }

    send: (d) =>
        @connection.socket\send d
        @status.total_bytes += #d
        @status.current_bytes += #d

    send_data: (data, port_provider) =>
        @status.current_bytes = 0
        @status.target_bytes = #data
        switch @transfer_params.mode
            when "S" then for i = 1, #data, 65536 do @send data\sub i, i + 65535
            when "B"
                for i = 1, #data, 65535
                    d = data\sub i, i + 65534
                    @send (if #d < 65535 then "\0" else "\128") .. string.char(#d / 256) .. string.char(#d % 256) .. d
            when "C"
                for i = 1, #data, 127
                    d = data\sub i, i + 126
                    @send string.char(#d) .. d
                @send "\0\128"
        @socket\send "226 Transfer complete"
        @connection.socket\close!
        if @connection.id == nil then port_provider @connection.port
    
    receive_data: (port_provider) =>
        data = ""
        while @connection.socket.is_open
            d = @connection.socket\receive!
            break if d == nil
            switch @transfer_params.mode
                when "S" then data = (data or "") .. d
                when "B"
                    descriptor = d\byte 1
                    size = d\byte(2) * 256 + d\byte(3)
                    data = (data or "") .. padstr d, size
                    if math.floor(descriptor / 128) == 1
                        @connection.socket\close!
                        break
                when "C"
                    b = d\byte 1
                    if b == 0 and math.floor(d\byte(2) / 128) == 1 
                        @connection.socket\close!
                        break
                    elseif math.floor(b / 128) == 0 then data = (data or "") .. d\sub(2, (b%128)+1)
                    elseif math.floor(b / 64) % 2 == 0 then data = (data or "") .. d\sub(2, 2)\rep(b % 64)
                    else
                        if @transfer_params.type == "A" or @transfer_params.type == "E" then data = (data or "") .. (" ")\rep(b % 64)
                        elseif @transfer_params.type == "I" or @transfer_params.type == "L" then data = (data or "") .. ("\0")\rep(b % 64)
        if @connection.id == nil then port_provider @connection.port
        return data

--- Server class for serving files over FTP.
class server
    --- Creates a new server object.
    -- @param modem The modem object to listen on
    -- @param port The port to listen for connections on (defaults to 21)
    -- @param auth A function that takes up to two arguments (username, password), and returns whether those arguments should authorize a user (default is no authorization)
    -- @param filesystem A filesystem object used for reading/writing files (defaults to the FS API)
    -- @param port_provider A function used for getting passive ports that is either called with no arguments and returns an unopened port, or called with one argument to free a closed port (defaults to a built-in implementation)
    new: (modem, port=21, auth=nil, filesystem=fs, port_provider=createPortProvider modem) =>
        @modem = modem
        @port = port
        @auth = auth
        @filesystem = filesystem
        @port_provider = port_provider
        @modem.open @port

    --- A table that holds all of the commands.
    commands: {
        USER: (self, state, username) ->
            return "501 Missing username" if username == nil
            state.username = username
            if self.auth == nil or self.auth state.username then return "230 User logged in, proceed."
            else return "331 User name okay, need password."
        PASS: (self, state, password) ->
            return "501 Missing password" if password == nil
            state.password = password
            if self.auth == nil then return "202 Password not required for this server."
            elseif self.auth state.username, state.password then return "230 User logged in, proceed."
            else return "530 Login incorrect."
        ACCT: (self, state) -> "502 ACCT command not implemented"
        CWD: (self, state, dir) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if dir == nil
            path = if dir\sub(1, 1) == "/" then dir\sub 2 else fs.combine state.dir, dir
            return "550 Not a directory" if not self.filesystem.isDir(path)
            state.dir = path
            return "200 OK"
        CDUP: (self, state) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            state.dir = fs.combine state.dir, ".."
            return "200 OK"
        SMNT: (self, state) -> "502 SMNT command not implemented"
        REIN: (self, state) ->
            state.username = nil
            state.password = nil
            state.dir = ""
            state.connection = nil
            state.transfer_params = {type: "A", mode: "S"}
            return "220 Service ready for new user."
        QUIT: (self, state) ->
            state.socket\send "221 Goodbye."
            state.socket\close!
        PORT: (self, state, port) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing ID/port" if port == nil
            p = port\match"(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)"
            return "501 Port specified is not correctly formatted" if tonumber(p[1]) == nil or tonumber(p[2]) == nil or tonumber(p[3]) == nil or tonumber(p[4]) == nil or tonumber(p[5]) == nil or tonumber(p[6]) == nil
            state.connection = {
                id: bit32.lshift(tonumber(p[1]), 24) + bit32.lshift(tonumber(p[2]), 16) + bit32.lshift(tonumber(p[3]), 8) + tonumber(p[4])
                port: bit32.lshift(tonumber(p[5]), 8) + tonumber(p[6])
            }
            return "200 OK"
        PASV: (self, state) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            state.connection = {id: nil, port: self.port_provider!}
            id = os.computerID!
            state.connection.task = self\_add_task (-> state.connection.socket = listen id, self.modem, state.connection.port), "passive listener " .. state.connection.port
            sleep 0.05
            return ("227 Entering passive mode. %d,%d,%d,%d,%d,%d")\format bit32.rshift(bit32.band(id, 0xFF000000), 24), 
                bit32.rshift(bit32.band(id, 0xFF0000), 16),
                bit32.rshift(bit32.band(id, 0xFF00), 8),
                bit32.band(id, 0xFF),
                bit32.rshift(bit32.band(state.connection.port, 0xFF00), 8),
                bit32.band state.connection.port, 0xFF
        TYPE: (self, state, type) ->
            c = type\sub(1, 1)\upper!
            return "504 Transfer type " .. c .. " not supported" if c == "E" or c == "L"
            return "501 Unknown transfer type " .. c if c != "A" and c != "I"
            state.transfer_params.type = c
            return "200 OK"
        STRU: (self, state) -> "502 STRU command not implemented"
        MODE: (self, state, mode) ->
            c = mode\sub(1, 1)\upper!
            return "501 Unknown transfer mode " .. c if c != "S" and c != "B" and c != "C"
            state.transfer_params.mode = c
            return "200 OK"
        RETR: (self, state, file) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if file == nil
            return "503 Bad sequence of commands" if state.connection.port == nil
            return "425 Data connection already open" if state.current_task != nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            if not self.filesystem.exists(path) or self.filesystem.isDir path
                state.connection = nil
                return "550 " .. (self.filesystem.isDir(path) and "Path is directory" or "File does not exist")
            state.current_task = self\_add_task (-> 
                    if state.connection.id != nil
                        state.connection.socket = connect os.computerID!, self.modem, state.connection.id, self.connection.port, 1
                    if state.connection.socket == nil
                        if state.connection.task != nil then self.tasks[state.connection.task] = nil
                        state.connection = nil
                        state.socket\send "425 Unable to open data connection."
                    local data
                    if state.transfer_params.type == "A"
                        fp = self.filesystem.open path, "r"
                        data = fp.readAll!
                        fp.close!
                    else
                        fp = self.filesystem.open path, "rb"
                        data = fp.read self.filesystem.getSize path
                        fp.close!
                    state\send_data data, self.port_provider
                    state.connection = nil
                    state.current_task = nil
                    state.status.current_bytes = nil
                    state.status.target_bytes = nil
                    state.status.current_command = nil
                ), "send data " .. file
            state.status.current_command = "RETR " .. path
            if state.connection.socket == nil then return "150 Opening data connection"
            else return "125 Data connection already open; transfer starting."
        STOR: (self, state, file) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if file == nil
            return "503 Bad sequence of commands" if state.connection.port == nil
            return "425 Data connection already open" if state.current_task != nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            if self.filesystem.isDir path
                state.connection = nil
                return "550 Path is directory"
            state.current_task = self\_add_task (->
                    if state.connection.id != nil
                        state.connection.socket = connect os.computerID!, self.modem, state.connection.id, self.connection.port, 1
                    if state.connection.socket == nil
                        if state.connection.task != nil then self.tasks[state.connection.task] = nil
                        state.connection = nil
                        state.socket\send "425 Unable to open data connection."
                    data = state\receive_data self.port_provider
                    local fp
                    if state.transfer_params.type == "A" then fp = self.filesystem.open path, "w"
                    else fp = self.filesystem.open path, "wb"
                    fp.write data
                    fp.close!
                    state.socket\send "250 Transfer complete"
                    state.connection = nil
                    state.current_task = nil
                    state.status.current_bytes = nil
                    state.status.target_bytes = nil
                    state.status.current_command = nil
                ), "receive data " .. file
            state.status.current_command = "STOR " .. path
            if state.connection.socket == nil then return "150 Opening data connection"
            else return "125 Data connection already open; transfer starting."
        STOU: (self, state) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "503 Bad sequence of commands" if state.connection.port == nil
            return "425 Data connection already open" if state.current_task != nil
            local name, path
            name = table.concat([string.char(math.random(65, 90)) for i = 1, 8]) .. "." .. table.concat([string.char(math.random(65, 90)) for i = 1, 3])
            path = fs.combine state.dir, name
            while self.filesystem.exists path or self.filesystem.isDir path
                name = table.concat([string.char(math.random(65, 90)) for i = 1, 8]) .. "." .. table.concat([string.char(math.random(65, 90)) for i = 1, 3])
                path = fs.combine state.dir, name
            state.current_task = self\_add_task (->
                    if state.connection.id != nil
                        state.connection.socket = connect os.computerID!, self.modem, state.connection.id, self.connection.port, 1
                    if state.connection.socket == nil
                        if state.connection.task != nil then self.tasks[state.connection.task] = nil
                        state.connection = nil
                        state.socket\send "425 Unable to open data connection."
                    data = state\receive_data self.port_provider
                    local fp
                    if state.transfer_params.type == "A" then fp = self.filesystem.open path, "w"
                    else fp = self.filesystem.open path, "wb"
                    fp.write 
                    fp.close!
                    state.socket\send "250 Transfer complete: " .. name
                    state.connection = nil
                    state.current_task = nil
                    state.status.current_bytes = nil
                    state.status.target_bytes = nil
                    state.status.current_command = nil
                ), "store unique " .. path
            state.status.current_command = "STOU " .. path
            if state.connection.socket == nil then return "150 Opening data connection"
            else return "125 Data connection already open; transfer starting."
        APPE: (self, state, file) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if file == nil
            return "503 Bad sequence of commands" if state.connection.port == nil
            return "425 Data connection already open" if state.current_task != nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            if self.filesystem.isDir path
                state.connection = nil
                return "550 Path is directory"
            state.current_task = self\_add_task (->
                    if state.connection.id != nil
                        state.connection.socket = connect os.computerID!, self.modem, state.connection.id, self.connection.port, 1
                    if state.connection.socket == nil
                        if state.connection.task != nil then self.tasks[state.connection.task] = nil
                        state.connection = nil
                        state.socket\send "425 Unable to open data connection."
                    data = state\receive_data self.port_provider
                    local fp
                    if state.transfer_params.type == "A" then fp = self.filesystem.open path, "a"
                    else fp = self.filesystem.open path, "ab"
                    fp.write data
                    fp.close!
                    state.socket\send "250 Transfer complete"
                    state.connection = nil
                    state.current_task = nil
                    state.status.current_bytes = nil
                    state.status.target_bytes = nil
                    state.status.current_command = nil
                ), "append " .. file
            state.status.current_command = "APPE " .. path
            if state.connection.socket == nil then return "150 Opening data connection"
            else return "125 Data connection already open; transfer starting."
        ALLO: (self, state) -> "502 ALLO command not implemented"
        REST: (self, state) -> "502 REST command not implemented"
        RNFR: (self, state, name) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if name == nil
            state.rename_from = name
            return "350 Awaiting name to rename to."
        RNTO: (self, state, name) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if name == nil
            return "503 Bad sequence of commands" if state.rename_from == nil
            old = if state.rename_from\sub(1, 1) == "/" then state.rename_from else fs.combine(state.dir, state.rename_from)
            new = if name\sub(1, 1) == "/" then name else fs.combine(state.dir, name)
            self.filesystem.move(old, new)
            state.rename_from = nil
            return "250 File operation succeeded"
        ABOR: (self, state) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "226 No data transfer in progress" if self.current_task == nil
            self.tasks[state.current_task] = nil
            state.socket\send "426 Data transfer aborted."
            return "226 Data transfer successfully aborted."
        DELE: (self, state, file) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if file == nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            return "550 File not found" if not fs.exists path
            return "550 Path is directory" if fs.isDir path
            self.filesystem.delete path
            return "250 File deleted"
        RMD: (self, state, file) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if file == nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            return "550 Directory not found" if not fs.exists path
            return "550 Path is not directory" if not fs.isDir path
            self.filesystem.delete path
            return "250 Directory deleted"
        MKD: (self, state, file) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "501 Missing file name" if file == nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            self.filesystem.makeDir path
            return '257 Created directory "' .. path .. '"'
        PWD: (self, state) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return '257 "' .. self.dir .. '"'
        LIST: (self, state, file=state.dir) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "202 Not implemented yet"
        NLST: (self, state, file=state.dir) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "503 Bad sequence of commands" if state.connection.port == nil
            return "425 Data connection already open" if state.current_task != nil
            path = if file\sub(1, 1) == "/" then file else fs.combine state.dir, file
            if not self.filesystem.isDir path
                state.connection = nil
                return "550 Path is not a directory"
            state.current_task = self\_add_task (->
                    if state.connection.id != nil
                        state.connection.socket = connect os.computerID!, self.modem, state.connection.id, self.connection.port, 1
                    if state.connection.socket == nil
                        if state.connection.task != nil then self.tasks[state.connection.task] = nil
                        state.connection = nil
                        state.socket\send "425 Unable to open data connection."
                    state\send_data table.concat([v for _,v in ipairs self.filesystem.list path], "\n"), self.port_provider
                    state.connection = nil
                    state.current_task = nil
                    state.status.current_bytes = nil
                    state.status.target_bytes = nil
                    state.status.current_command = nil
                ), "name list " .. file
            state.status.current_command = "NLST " .. path
            if state.connection.socket == nil then return "150 Opening data connection"
            else return "125 Data connection already open; transfer starting."
        SITE: (self, state) -> "202 Not implemented"
        SYST: (self, state) -> "215 UNKNOWN CraftOS"
        STAT: (self, state) ->
            return "530 Not logged in." if self.auth != nil and not self.auth state.username, state.password
            return "211-Status of '#{os.computerLabel!}'\n Connected from ID #{state.socket.id}
 Logged in as #{state.username}
 TYPE: #{state.transfer.params == "A" and "ASCII" or "Image"}, STRUcture: File, Mode: #{state.transfer.params == "S" and "Stream" or (state.transfer.params == "B" and "Block" or "Compressed")}
 Total bytes transferred for session: #{state.status.total_bytes}\n" .. (self.current_task == nil and "No data connection" or "#{state.connection.id == nil and "Passive" or "Active"} data transfer from #{state.connection.socket.id} port #{state.connection.port}\n#{state.status.current_command} (#{state.status.target_bytes}/#{state.status.current_bytes})") .. "
211 End of status"
        HELP: (self, state, cmd) -> "202 Not implemented (yet)"
        NOOP: (self, state) -> "200 NOOP command successful"
    }

    _add_task: (func, name) =>
        return if @tasks == nil
        id = #@tasks+1
        @tasks[id] = {coro: coroutine.create(func), filter: nil, _name: name}
        return id

    _listen: =>
        while true -- change this to a conditional?
            socket = listen os.computerID!, @modem, @port
            @_add_task (-> @_run_connection server_connection socket), "connection " .. socket.id

    _run_connection: (state) =>
        state.socket\send "220 Hello!"
        while state.socket.is_open
            req, err = state.socket\receive 3600
            break if req == nil
            command, arg = req
            if req\find " " then command, arg = req\sub(1, req\find" " - 1)\upper!, req\sub req\find" " + 1
            if @commands[command] == nil then state.socket\send "500 Unknown command '" .. command .. "'"
            else
                if arg == "" then arg = nil
                reply = @commands[command] @, state, arg
                break unless state.socket.is_open
                if @commands[command] != nil then state.socket\send reply
        state.socket\close!

    --- Listens for FTP requests.
    listen: =>
        -- Since many sockets may be listening at the same time, we'll be using
        -- a simple coroutine manager to handle events.
        @tasks = {{coro: coroutine.create(-> @_listen!), filter: nil, _name: "root listener"}}
        while #@tasks > 0
            ev = {os.pullEvent!}
            delete = {}
            for i,v in ipairs(@tasks)
                if v.filter == nil or v.filter == ev[1]
                    ok, v.filter = coroutine.resume v.coro, table.unpack ev
                    if not ok then print (v.name or "unknown") .. ": " .. v.filter
                    if not ok or coroutine.status(v.coro) != "suspended" then table.insert delete, i
            for _,i in ipairs(delete) do @tasks[i] = nil
        @tasks = nil

return {:client, :server}
    