local connect, listen
do
  local _obj_0 = require("socket")
  connect, listen = _obj_0.connect, _obj_0.listen
end
local padstr
padstr = function(str, size)
  if #str < size then
    return str .. (" "):rep(size - str)
  else
    return str:sub(1, size)
  end
end
local createPortProvider
createPortProvider = function(modem)
  local usedPorts = { }
  return function(num)
    if num == nil then
      if usedPorts[20] == nil then
        usedPorts[20] = true
        return 20
      else
        local i = 5000
        while i < 65536 and usedPorts[i] and modem.isOpen(i) do
          i = i + 1
        end
        if i > 65535 then
          return nil
        else
          return i
        end
      end
    else
      usedPorts[num] = nil
    end
  end
end
local client
do
  local _class_0
  local _base_0 = {
    _send_command = function(self, command)
      if not self.connection.is_open then
        return false, 421, "Connection closed"
      end
      if command ~= nil then
        local ok, err = self.connection:send(command)
        if not ok then
          error("Could not send command: " .. err, 2)
        end
      end
      local res, err = self.connection:receive()
      if res == nil then
        error("Could not receive reply: " .. err, 2)
      end
      local code = res:sub(1, 3)
      if tonumber(code) == nil then
        error("Malformed reply (invalid code): " .. res)
      end
      local reply = ""
      if res:sub(4, 4) == '-' then
        for line in res:sub(5):gmatch("[^\n]+") do
          if line:sub(1, 4) == code .. " " then
            reply = reply .. line:sub(5)
            break
          else
            reply = reply .. (line .. "\n")
          end
        end
      elseif res:sub(4, 4) == ' ' then
        reply = res:sub(5)
      else
        error("Malformed reply (invalid code separator):" .. res)
      end
      local _exp_0 = math.floor(tonumber(code) / 100)
      if 1 == _exp_0 then
        return self:_send_command()
      elseif 2 == _exp_0 or 3 == _exp_0 then
        return true, tonumber(code), reply
      elseif 4 == _exp_0 or 5 == _exp_0 then
        return false, tonumber(code), reply
      else
        return error("Malformed reply (invalid code): " .. code)
      end
    end,
    _receive_data = function(self, command)
      if self.pasv then
        local port = self:pasv()
        if port == nil then
          error("Ran out of ports for data connection")
        end
        local id = os.computerID()
        local ok, code, res = self:_send_command("PORT " .. math.floor(id / 16777216) .. "," .. (math.floor(id / 65536) % 256) .. "," .. (math.floor(id / 256) % 256) .. "," .. (id % 256) .. "," .. math.floor(port / 256) .. "," .. (id % 256))
        if code ~= 200 then
          return nil, code, res
        end
        local data, data_connection, err
        parallel.waitForAll((function()
          ok, code, err = self:_send_command(command)
          if not ok then
            data_connection:close()
            return os.queueEvent("socket_close_aaaaaaaaaaa")
          end
        end), (function()
          data_connection = listen(os.computerID(), self.modem, port, self.timeout)
          while data_connection.is_open do
            local d = data_connection:receive()
            if d == nil then
              break
            end
            local _exp_0 = self.transfer_params.mode
            if "S" == _exp_0 then
              data = (data or "") .. d
            elseif "B" == _exp_0 then
              local descriptor = d:byte(1)
              local size = d:byte(2) * 256 + d:byte(3)
              data = (data or "") .. padstr(d, size)
              if math.floor(descriptor / 128) == 1 then
                data_connection:close()
                break
              end
            elseif "C" == _exp_0 then
              local b = d:byte(1)
              if b == 0 and math.floor(d:byte(2) / 128) == 1 then
                data_connection:close()
                break
              elseif math.floor(b / 128) == 0 then
                data = (data or "") .. d:sub(2, (b % 128) + 1)
              elseif math.floor(b / 64) % 2 == 0 then
                data = (data or "") .. d:sub(2, 2):rep(b % 64)
              else
                if self.transfer_params.type == "A" or self.transfer_params.type == "E" then
                  data = (data or "") .. (" "):rep(b % 64)
                elseif self.transfer_params.type == "I" or self.transfer_params.type == "L" then
                  data = (data or "") .. ("\0"):rep(b % 64)
                end
              end
            end
          end
        end))
        if data_connection.is_open then
          data_connection:close()
        end
        self:pasv(port)
        if self.transfer_params.type == "A" and data ~= nil then
          data = data:gsub("[\128-\255]", "?")
        end
        return data, code, err
      else
        local ok, code, res = self:_send_command("PASV")
        if code ~= 227 then
          return false, code, res
        end
        local i1, i2, i3, i4, p1, p2 = res:match(("(%d+),"):rep(5) .. "(%d+)")
        local id = tonumber(i1) * 16777216 + tonumber(i2) * 65536 + tonumber(i3) * 255 + tonumber(i4)
        local port = tonumber(p1) * 256 + tonumber(p2)
        local data_connection = connect(os.computerID(), self.modem, id, port, self.timeout)
        if data_connection == nil then
          return false, 0, "Could not connect to server"
        end
        local data, err
        parallel.waitForAll((function()
          ok, code, err = self:_send_command(command)
          if not ok then
            data_connection:close()
            return os.queueEvent("socket_close_aaaaaaaaaaa")
          end
        end), (function()
          while data_connection.is_open do
            local d = data_connection:receive()
            if d == nil then
              break
            end
            local _exp_0 = self.transfer_params.mode
            if "S" == _exp_0 then
              data = (data or "") .. d
            elseif "B" == _exp_0 then
              local descriptor = d:byte(1)
              local size = d:byte(2) * 256 + d:byte(3)
              data = (data or "") .. padstr(d, size)
              if math.floor(descriptor / 128) == 1 then
                data_connection:close()
                break
              end
            elseif "C" == _exp_0 then
              local b = d:byte(1)
              if b == 0 and math.floor(d:byte(2) / 128) == 1 then
                data_connection:close()
                break
              elseif math.floor(b / 128) == 0 then
                data = (data or "") .. d:sub(2, (b % 128) + 1)
              elseif math.floor(b / 64) % 2 == 0 then
                data = (data or "") .. d:sub(2, 2):rep(b % 64)
              else
                if self.transfer_params.type == "A" or self.transfer_params.type == "E" then
                  data = (data or "") .. (" "):rep(b % 64)
                elseif self.transfer_params.type == "I" or self.transfer_params.type == "L" then
                  data = (data or "") .. ("\0"):rep(b % 64)
                end
              end
            end
          end
        end))
        if data_connection.is_open then
          data_connection:close()
        end
        if self.transfer_params.type == "A" then
          data = data:gsub("[\128-\255]", "?")
        end
        return data, code, err
      end
    end,
    _send_data = function(self, command, data)
      if self.transfer_params.type == "A" then
        data = data:gsub("[\128-\255]", "?")
      end
      if self.pasv then
        local port = self:pasv()
        if port == nil then
          error("Ran out of ports for data connection")
        end
        local id = os.computerID()
        local ok, code, res = self:_send_command("PORT " .. math.floor(id / 16777216) .. "," .. (math.floor(id / 65536) % 256) .. "," .. (math.floor(id / 256) % 256) .. "," .. (id % 256) .. "," .. math.floor(port / 256) .. "," .. (id % 256))
        if code ~= 200 then
          return false, code, res
        end
        local data_connection, err
        parallel.waitForAny((function()
          ok, code, err = self:_send_command(command)
          if ok then
            while data_connection.is_open do
              os.pullEvent()
            end
          end
        end), (function()
          data_connection = listen(os.computerID(), self.modem, port, self.timeout)
          if not (data_connection.is_open) then
            return 
          end
          local _exp_0 = self.transfer_params.mode
          if "S" == _exp_0 then
            for i = 1, #data, 65536 do
              data_connection:send(data:sub(i, i + 65535))
            end
          elseif "B" == _exp_0 then
            for i = 1, #data, 65535 do
              local d = data:sub(i, i + 65534)
              data_connection:send(((function()
                if #d < 65535 then
                  return "\0"
                else
                  return "\128"
                end
              end)()) .. string.char(#d / 256) .. string.char(#d % 256) .. d)
            end
          elseif "C" == _exp_0 then
            for i = 1, #data, 127 do
              local d = data:sub(i, i + 126)
              data_connection:send(string.char(#d) .. d)
            end
            data_connection:send("\0\128")
          end
          return data_connection:close()
        end))
        self:pasv(port)
        return ok, code, err
      else
        local ok, code, res = self:_send_command("PASV")
        if code ~= 227 then
          return false, code, res
        end
        local i1, i2, i3, i4, p1, p2 = res:match(("(%d+),"):rep(5) .. "(%d+)")
        local id = tonumber(i1) * 16777216 + tonumber(i2) * 65536 + tonumber(i3) * 255 + tonumber(i4)
        local port = tonumber(p1) * 256 + tonumber(p2)
        local data_connection = connect(os.computerID(), self.modem, id, port, self.timeout)
        if data_connection == nil then
          return false, 0, "Could not connect to server"
        end
        local err
        ok, code, err = self:_send_command(command)
        if not ok then
          data_connection:close()
          return ok, code, err
        end
        local _exp_0 = self.transfer_params.mode
        if "S" == _exp_0 then
          for i = 1, #data, 65536 do
            data_connection:send(data:sub(i, i + 65535))
          end
        elseif "B" == _exp_0 then
          for i = 1, #data, 65535 do
            local d = data:sub(i, i + 65534)
            data_connection:send(((function()
              if #d < 65535 then
                return "\0"
              else
                return "\128"
              end
            end)()) .. string.char(#d / 256) .. string.char(#d % 256) .. d)
          end
        elseif "C" == _exp_0 then
          for i = 1, #data, 127 do
            local d = data:sub(i, i + 126)
            data_connection:send(string.char(#d) .. d)
          end
          data_connection:send("\0\128")
        end
        data_connection:close()
        return true
      end
    end,
    login = function(self, username, password)
      if type(username) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(username) .. ")", 2)
      end
      if password ~= nil and type(password) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(password) .. ")", 2)
      end
      local ok, code, err = self:_send_command("USER " .. username)
      local _exp_0 = code
      if 230 == _exp_0 then
        return true
      elseif 500 == _exp_0 or 501 == _exp_0 or 421 == _exp_0 or 530 == _exp_0 then
        return false, err
      elseif 331 == _exp_0 or 332 == _exp_0 then
        if password == nil then
          return false, "Password required"
        end
      else
        error("Malformed reply (invalid code): " .. code)
      end
      ok, code, err = self:_send_command("PASS " .. password)
      local _exp_1 = code
      if 230 == _exp_1 then
        return true
      elseif 202 == _exp_1 then
        return true
      elseif 500 == _exp_1 or 502 == _exp_1 or 421 == _exp_1 or 530 == _exp_1 then
        return false, err
      elseif 332 == _exp_1 then
        return false, err
      else
        return error("Malformed reply (invalid code): " .. code)
      end
    end,
    close = function(self)
      self:_send_command("QUIT")
      return self.connection:close()
    end,
    setTransferParams = function(self, dtype, mode)
      if dtype == nil then
        dtype = self.transfer_params.type
      end
      if mode == nil then
        mode = self.transfer_params.mode
      end
      if type(dtype) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(dtype) .. ")", 2)
      end
      if type(mode) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(mode) .. ")", 2)
      end
      if dtype ~= "A" and dtype ~= "I" then
        error("bad argument #1 (invalid data type)", 2)
      end
      if mode ~= "S" and mode ~= "B" and mode ~= "C" then
        error("bad argument #2 (invalid transmission mode)", 2)
      end
      if dtype ~= self.transfer_params.type then
        local ok, code, err = self:_send_command("TYPE " .. dtype)
        if code == 200 then
          self.transfer_params.type = dtype
        end
      end
      if mode ~= self.transfer_params.mode then
        local ok, code, err = self:_send_command("MODE " .. mode)
        if code == 200 then
          self.transfer_params.mode = mode
        end
      end
      return self.transfer_params.type, self.transfer_params.mode
    end,
    list = function(self, path)
      if type(path) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(path) .. ")", 2)
      end
      if path == "" then
        path = "/"
      end
      local o
      if self.transfer_params.type ~= "A" then
        o = self.transfer_params.type
        if self:setTransferParams("A") ~= "A" then
          error("Could not switch to ASCII data type")
        end
      end
      local data, code, err = self:_receive_data("NLST " .. path)
      if o then
        self:setTransferParams(o)
      end
      if not data then
        error(err .. " (" .. code .. ")", 2)
      end
      local _accum_0 = { }
      local _len_0 = 1
      for line in data:gmatch("[^\r\n]+") do
        _accum_0[_len_0] = line
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end,
    exists = function(self, path)
      return #(function()
        local _accum_0 = { }
        local _len_0 = 1
        for _, v in ipairs(self:list(fs.getDir(path))) do
          if v == fs.getName(path) then
            _accum_0[_len_0] = v
            _len_0 = _len_0 + 1
          end
        end
        return _accum_0
      end)() > 0
    end,
    isDir = function(self, path)
      if type(path) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(path) .. ")", 2)
      end
      if path == "" then
        path = "/"
      end
      local ok, code, err = self:_send_command("CWD " .. path)
      local _exp_0 = code
      if 533 == _exp_0 or 550 == _exp_0 then
        return false
      elseif 200 == _exp_0 or 250 == _exp_0 then
        self:_send_command("CWD /")
        return true
      else
        return error(err .. " (" .. code .. ")", 2)
      end
    end,
    isReadOnly = function(self)
      return false
    end,
    getSize = function(self, path)
      if type(path) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(path) .. ")", 2)
      end
      if path == "" then
        path = "/"
      end
      local data, code, err = self:_receive_data("RETR " .. path)
      if data == nil then
        error(err .. " (" .. code .. ")", 2)
      end
      return #data
    end,
    getFreeSpace = function(self)
      return 1000000
    end,
    makeDir = function(self, path)
      if type(path) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(path) .. ")", 2)
      end
      local ok, code, err = self:_send_command("MKD " .. path)
      if not ok then
        return error(err .. " (" .. code .. ")", 2)
      end
    end,
    move = function(self, fromPath, toPath)
      if type(fromPath) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(fromPath) .. ")", 2)
      end
      if type(toPath) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(toPath) .. ")", 2)
      end
      local ok, code, err = self:_send_command("RNFR " .. fromPath)
      if not ok then
        error(err .. " (" .. code .. ")", 2)
      end
      ok, code, err = self:_send_command("RNTO " .. toPath)
      if not ok then
        return error(err .. " (" .. code .. ")", 2)
      end
    end,
    copy = function(self, fromPath, toPath)
      if type(fromPath) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(fromPath) .. ")", 2)
      end
      if type(toPath) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(toPath) .. ")", 2)
      end
      local o
      if self.transfer_params.type ~= "I" then
        o = self.transfer_params.type
        if self:setTransferParams("I") ~= "I" then
          error("Could not switch to Image data type")
        end
      end
      local data, code, err = self:_receive_data("RETR " .. fromPath)
      if data == nil then
        if o then
          self:setTransferParams(o)
        end
        error(err .. " (" .. code .. ")", 2)
      end
      local ok
      ok, code, err = self:_send_data("STOR " .. toPath, data)
      if not ok then
        if o then
          self:setTransferParams(o)
        end
        return error(err .. " (" .. code .. ")", 2)
      end
    end,
    delete = function(self, path)
      if type(path) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(path) .. ")", 2)
      end
      local ok, code, err = self:_send_command("DELE " .. path)
      if not ok then
        ok = self:_send_command("RMD " .. path)
        if ok then
          for f in ipairs(self:list(path)) do
            self:delete(fs.combine(path, f))
          end
        else
          return error(err .. " (" .. code .. ")", 2)
        end
      end
    end,
    open = function(self, path, mode)
      if type(path) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(path) .. ")", 2)
      end
      if type(mode) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(mode) .. ")", 2)
      end
      local _exp_0 = mode
      if "r" == _exp_0 then
        if self:setTransferParams("A") ~= "A" then
          error("Could not switch to ASCII data type")
        end
        local data, code, err = self:_receive_data("RETR " .. path)
        if data == nil then
          return nil, err .. " (" .. code .. ")"
        end
        local offset = 1
        return {
          close = function()
            return nil
          end,
          readLine = function()
            if offset >= #data then
              return nil
            end
            local i = data:find("\n", offset) or #data + 1
            local l = data:sub(offset, i - 1)
            offset = i + 1
            return l
          end,
          readAll = function()
            if offset >= #data then
              return nil
            end
            local l = data:sub(offset)
            offset = #data
            return l
          end,
          read = function(size)
            if offset >= #data then
              return nil
            end
            local l = data:sub(offset, offset + size)
            offset = offset + size
            return l
          end,
          seek = function(whence, pos)
            pos = pos or 0
            if type(whence) == "number" and type(pos) == nil then
              pos = whence
              whence = "cur"
            end
            local _exp_1 = whence
            if "cur" == _exp_1 then
              offset = offset + math.max(math.min(pos, #data), 0)
            elseif "set" == _exp_1 then
              offset = math.max(math.min(pos, #data), 0)
            elseif "end" == _exp_1 then
              offset = math.max(math.min(#data - pos, #data), 0)
            end
            return offset
          end
        }
      elseif "w" == _exp_0 then
        local data = ""
        local offset = 1
        local t = {
          flush = function()
            if self:setTransferParams("A") ~= "A" then
              error("Could not switch to ASCII data type")
            end
            local ok, code, err = self:_send_data("STOR " .. path, data)
            if not ok then
              return error(err .. " (" .. code .. ")")
            end
          end,
          write = function(str)
            data = data:sub(1, offset - 1) .. str .. data:sub(offset)
            offset = offset + #str
          end,
          writeLine = function(str)
            data = data:sub(1, offset - 1) .. str .. "\n" .. data:sub(offset)
            offset = offset + #str + 1
          end,
          seek = function(whence, pos)
            pos = pos or 0
            if type(whence) == "number" and type(pos) == nil then
              pos = whence
              whence = "cur"
            end
            local _exp_1 = whence
            if "cur" == _exp_1 then
              offset = offset + math.max(math.min(pos, #data), 0)
            elseif "set" == _exp_1 then
              offset = math.max(math.min(pos, #data), 0)
            elseif "end" == _exp_1 then
              offset = math.max(math.min(#data - pos, #data), 0)
            end
            return offset
          end
        }
        t.close = t.flush
        return t
      elseif "a" == _exp_0 then
        local data = ""
        local offset = 1
        return {
          close = function()
            if self:setTransferParams("A") ~= "A" then
              error("Could not switch to ASCII data type")
            end
            local ok, code, err = self:_send_data("STOA " .. path, data)
            if not ok then
              return error(err .. " (" .. code .. ")")
            end
          end,
          write = function(str)
            data = data:sub(1, offset - 1) .. str .. data:sub(offset)
            offset = offset + #str
          end,
          writeLine = function(str)
            data = data:sub(1, offset - 1) .. str .. "\n" .. data:sub(offset)
            offset = offset + #str + 1
          end,
          flush = function()
            return nil
          end
        }
      elseif "rb" == _exp_0 then
        if self:setTransferParams("I") ~= "I" then
          error("Could not switch to Image data type")
        end
        local data, code, err = self:_receive_data("RETR " .. path)
        if data == nil then
          return nil, err .. " (" .. code .. ")"
        end
        local offset = 1
        return {
          close = function()
            return nil
          end,
          readAll = function()
            if offset >= #data then
              return nil
            end
            local l = data:sub(offset)
            offset = #data
            return l
          end,
          read = function(size)
            if offset >= #data then
              return nil
            end
            if size == nil then
              offset = offset + 1
              return data:byte(offset - 1)
            end
            local l = data:sub(offset, offset + size)
            offset = offset + size
            return l
          end,
          seek = function(whence, pos)
            pos = pos or 0
            if type(whence) == "number" and type(pos) == nil then
              pos = whence
              whence = "cur"
            end
            local _exp_1 = whence
            if "cur" == _exp_1 then
              offset = offset + math.max(math.min(pos, #data), 0)
            elseif "set" == _exp_1 then
              offset = math.max(math.min(pos, #data), 0)
            elseif "end" == _exp_1 then
              offset = math.max(math.min(#data - pos, #data), 0)
            end
            return offset
          end
        }
      elseif "wb" == _exp_0 then
        local data = ""
        local offset = 1
        local t = {
          flush = function()
            if self:setTransferParams("I") ~= "I" then
              error("Could not switch to Image data type")
            end
            local ok, code, err = self:_send_data("STOR " .. path, data)
            if not ok then
              return error(err .. " (" .. code .. ")")
            end
          end,
          write = function(str)
            data = data:sub(1, offset - 1) .. ((function()
              if type(str) == "number" then
                return string.char(str)
              else
                return str
              end
            end)()) .. data:sub(offset)
            offset = offset + #str
          end,
          seek = function(whence, pos)
            pos = pos or 0
            if type(whence) == "number" and type(pos) == nil then
              pos = whence
              whence = "cur"
            end
            local _exp_1 = whence
            if "cur" == _exp_1 then
              offset = offset + math.max(math.min(pos, #data), 0)
            elseif "set" == _exp_1 then
              offset = math.max(math.min(pos, #data), 0)
            elseif "end" == _exp_1 then
              offset = math.max(math.min(#data - pos, #data), 0)
            end
            return offset
          end
        }
        t.close = t.flush
        return t
      elseif "ab" == _exp_0 then
        local data = ""
        local offset = 1
        return {
          close = function()
            if self:setTransferParams("I") ~= "I" then
              error("Could not switch to Image data type")
            end
            local ok, code, err = self:_send_data("STOA " .. path, data)
            if not ok then
              return error(err .. " (" .. code .. ")")
            end
          end,
          write = function(str)
            data = data:sub(1, offset - 1) .. ((function()
              if type(str) == "number" then
                return string.char(str)
              else
                return str
              end
            end)()) .. data:sub(offset)
            offset = offset + #str
          end,
          flush = function()
            return nil
          end
        }
      else
        return nil, "Unknown mode \"" .. mode .. '"'
      end
    end,
    find = function(self)
      return nil
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, modem, id, port, pasv, timeout)
      if port == nil then
        port = 21
      end
      if pasv == nil then
        pasv = false
      end
      if timeout == nil then
        timeout = 5
      end
      self.modem = modem
      self.timeout = timeout
      local err
      self.connection, err = connect(os.computerID(), modem, id, port, timeout)
      if self.connection == nil then
        error("Could not connect to server: " .. (err or ""), 2)
      end
      self.pasv = pasv
      self.transfer_params = {
        type = "A",
        mode = "S"
      }
      return self:_send_command()
    end,
    __base = _base_0,
    __name = "client"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  client = _class_0
end
local server_connection
do
  local _class_0
  local _base_0 = {
    send = function(self, d)
      self.connection.socket:send(d)
      self.status.total_bytes = self.status.total_bytes + #d
      self.status.current_bytes = self.status.current_bytes + #d
    end,
    send_data = function(self, data, port_provider)
      self.status.current_bytes = 0
      self.status.target_bytes = #data
      local _exp_0 = self.transfer_params.mode
      if "S" == _exp_0 then
        for i = 1, #data, 65536 do
          self:send(data:sub(i, i + 65535))
        end
      elseif "B" == _exp_0 then
        for i = 1, #data, 65535 do
          local d = data:sub(i, i + 65534)
          self:send(((function()
            if #d < 65535 then
              return "\0"
            else
              return "\128"
            end
          end)()) .. string.char(#d / 256) .. string.char(#d % 256) .. d)
        end
      elseif "C" == _exp_0 then
        for i = 1, #data, 127 do
          local d = data:sub(i, i + 126)
          self:send(string.char(#d) .. d)
        end
        self:send("\0\128")
      end
      self.socket:send("226 Transfer complete")
      self.connection.socket:close()
      if self.connection.id == nil then
        return port_provider(self.connection.port)
      end
    end,
    receive_data = function(self, port_provider)
      local data = ""
      while self.connection.socket.is_open do
        local d = self.connection.socket:receive()
        if d == nil then
          break
        end
        local _exp_0 = self.transfer_params.mode
        if "S" == _exp_0 then
          data = (data or "") .. d
        elseif "B" == _exp_0 then
          local descriptor = d:byte(1)
          local size = d:byte(2) * 256 + d:byte(3)
          data = (data or "") .. padstr(d, size)
          if math.floor(descriptor / 128) == 1 then
            self.connection.socket:close()
            break
          end
        elseif "C" == _exp_0 then
          local b = d:byte(1)
          if b == 0 and math.floor(d:byte(2) / 128) == 1 then
            self.connection.socket:close()
            break
          elseif math.floor(b / 128) == 0 then
            data = (data or "") .. d:sub(2, (b % 128) + 1)
          elseif math.floor(b / 64) % 2 == 0 then
            data = (data or "") .. d:sub(2, 2):rep(b % 64)
          else
            if self.transfer_params.type == "A" or self.transfer_params.type == "E" then
              data = (data or "") .. (" "):rep(b % 64)
            elseif self.transfer_params.type == "I" or self.transfer_params.type == "L" then
              data = (data or "") .. ("\0"):rep(b % 64)
            end
          end
        end
      end
      if self.connection.id == nil then
        port_provider(self.connection.port)
      end
      return data
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, socket)
      self.socket = socket
      self.dir = ""
      self.transfer_params = {
        type = "A",
        mode = "S"
      }
      self.status = {
        total_bytes = 0,
        current_bytes = nil,
        target_bytes = nil,
        current_command = nil
      }
    end,
    __base = _base_0,
    __name = "server_connection"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  server_connection = _class_0
end
local server
do
  local _class_0
  local _base_0 = {
    commands = {
      USER = function(self, state, username)
        if username == nil then
          return "501 Missing username"
        end
        state.username = username
        if self.auth == nil or self.auth(state.username) then
          return "230 User logged in, proceed."
        else
          return "331 User name okay, need password."
        end
      end,
      PASS = function(self, state, password)
        if password == nil then
          return "501 Missing password"
        end
        state.password = password
        if self.auth == nil then
          return "202 Password not required for this server."
        elseif self.auth(state.username, state.password) then
          return "230 User logged in, proceed."
        else
          return "530 Login incorrect."
        end
      end,
      ACCT = function(self, state)
        return "502 ACCT command not implemented"
      end,
      CWD = function(self, state, dir)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if dir == nil then
          return "501 Missing file name"
        end
        local path
        if dir:sub(1, 1) == "/" then
          path = dir:sub(2)
        else
          path = fs.combine(state.dir, dir)
        end
        if not self.filesystem.isDir(path) then
          return "550 Not a directory"
        end
        state.dir = path
        return "200 OK"
      end,
      CDUP = function(self, state)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        state.dir = fs.combine(state.dir, "..")
        return "200 OK"
      end,
      SMNT = function(self, state)
        return "502 SMNT command not implemented"
      end,
      REIN = function(self, state)
        state.username = nil
        state.password = nil
        state.dir = ""
        state.connection = nil
        state.transfer_params = {
          type = "A",
          mode = "S"
        }
        return "220 Service ready for new user."
      end,
      QUIT = function(self, state)
        state.socket:send("221 Goodbye.")
        return state.socket:close()
      end,
      PORT = function(self, state, port)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if port == nil then
          return "501 Missing ID/port"
        end
        local p = port:match("(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)")
        if tonumber(p[1]) == nil or tonumber(p[2]) == nil or tonumber(p[3]) == nil or tonumber(p[4]) == nil or tonumber(p[5]) == nil or tonumber(p[6]) == nil then
          return "501 Port specified is not correctly formatted"
        end
        state.connection = {
          id = bit32.lshift(tonumber(p[1]), 24) + bit32.lshift(tonumber(p[2]), 16) + bit32.lshift(tonumber(p[3]), 8) + tonumber(p[4]),
          port = bit32.lshift(tonumber(p[5]), 8) + tonumber(p[6])
        }
        return "200 OK"
      end,
      PASV = function(self, state)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        state.connection = {
          id = nil,
          port = self.port_provider()
        }
        local id = os.computerID()
        state.connection.task = self:_add_task((function()
          state.connection.socket = listen(id, self.modem, state.connection.port)
        end), "passive listener " .. state.connection.port)
        sleep(0.05)
        return ("227 Entering passive mode. %d,%d,%d,%d,%d,%d"):format(bit32.rshift(bit32.band(id, 0xFF000000), 24), bit32.rshift(bit32.band(id, 0xFF0000), 16), bit32.rshift(bit32.band(id, 0xFF00), 8), bit32.band(id, 0xFF), bit32.rshift(bit32.band(state.connection.port, 0xFF00), 8), bit32.band(state.connection.port, 0xFF))
      end,
      TYPE = function(self, state, type)
        local c = type:sub(1, 1):upper()
        if c == "E" or c == "L" then
          return "504 Transfer type " .. c .. " not supported"
        end
        if c ~= "A" and c ~= "I" then
          return "501 Unknown transfer type " .. c
        end
        state.transfer_params.type = c
        return "200 OK"
      end,
      STRU = function(self, state)
        return "502 STRU command not implemented"
      end,
      MODE = function(self, state, mode)
        local c = mode:sub(1, 1):upper()
        if c ~= "S" and c ~= "B" and c ~= "C" then
          return "501 Unknown transfer mode " .. c
        end
        state.transfer_params.mode = c
        return "200 OK"
      end,
      RETR = function(self, state, file)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if file == nil then
          return "501 Missing file name"
        end
        if state.connection.port == nil then
          return "503 Bad sequence of commands"
        end
        if state.current_task ~= nil then
          return "425 Data connection already open"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        if not self.filesystem.exists(path) or self.filesystem.isDir(path) then
          state.connection = nil
          return "550 " .. (self.filesystem.isDir(path) and "Path is directory" or "File does not exist")
        end
        state.current_task = self:_add_task((function()
          if state.connection.id ~= nil then
            state.connection.socket = connect(os.computerID(), self.modem, state.connection.id, self.connection.port, 1)
          end
          if state.connection.socket == nil then
            if state.connection.task ~= nil then
              self.tasks[state.connection.task] = nil
            end
            state.connection = nil
            state.socket:send("425 Unable to open data connection.")
          end
          local data
          if state.transfer_params.type == "A" then
            local fp = self.filesystem.open(path, "r")
            data = fp.readAll()
            fp.close()
          else
            local fp = self.filesystem.open(path, "rb")
            data = fp.read(self.filesystem.getSize(path))
            fp.close()
          end
          state:send_data(data, self.port_provider)
          state.connection = nil
          state.current_task = nil
          state.status.current_bytes = nil
          state.status.target_bytes = nil
          state.status.current_command = nil
        end), "send data " .. file)
        state.status.current_command = "RETR " .. path
        if state.connection.socket == nil then
          return "150 Opening data connection"
        else
          return "125 Data connection already open; transfer starting."
        end
      end,
      STOR = function(self, state, file)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if file == nil then
          return "501 Missing file name"
        end
        if state.connection.port == nil then
          return "503 Bad sequence of commands"
        end
        if state.current_task ~= nil then
          return "425 Data connection already open"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        if self.filesystem.isDir(path) then
          state.connection = nil
          return "550 Path is directory"
        end
        state.current_task = self:_add_task((function()
          if state.connection.id ~= nil then
            state.connection.socket = connect(os.computerID(), self.modem, state.connection.id, self.connection.port, 1)
          end
          if state.connection.socket == nil then
            if state.connection.task ~= nil then
              self.tasks[state.connection.task] = nil
            end
            state.connection = nil
            state.socket:send("425 Unable to open data connection.")
          end
          local data = state:receive_data(self.port_provider)
          local fp
          if state.transfer_params.type == "A" then
            fp = self.filesystem.open(path, "w")
          else
            fp = self.filesystem.open(path, "wb")
          end
          fp.write(data)
          fp.close()
          state.socket:send("250 Transfer complete")
          state.connection = nil
          state.current_task = nil
          state.status.current_bytes = nil
          state.status.target_bytes = nil
          state.status.current_command = nil
        end), "receive data " .. file)
        state.status.current_command = "STOR " .. path
        if state.connection.socket == nil then
          return "150 Opening data connection"
        else
          return "125 Data connection already open; transfer starting."
        end
      end,
      STOU = function(self, state)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if state.connection.port == nil then
          return "503 Bad sequence of commands"
        end
        if state.current_task ~= nil then
          return "425 Data connection already open"
        end
        local name, path
        name = table.concat((function()
          local _accum_0 = { }
          local _len_0 = 1
          for i = 1, 8 do
            _accum_0[_len_0] = string.char(math.random(65, 90))
            _len_0 = _len_0 + 1
          end
          return _accum_0
        end)()) .. "." .. table.concat((function()
          local _accum_0 = { }
          local _len_0 = 1
          for i = 1, 3 do
            _accum_0[_len_0] = string.char(math.random(65, 90))
            _len_0 = _len_0 + 1
          end
          return _accum_0
        end)())
        path = fs.combine(state.dir, name)
        while self.filesystem.exists(path or self.filesystem.isDir(path)) do
          name = table.concat((function()
            local _accum_0 = { }
            local _len_0 = 1
            for i = 1, 8 do
              _accum_0[_len_0] = string.char(math.random(65, 90))
              _len_0 = _len_0 + 1
            end
            return _accum_0
          end)()) .. "." .. table.concat((function()
            local _accum_0 = { }
            local _len_0 = 1
            for i = 1, 3 do
              _accum_0[_len_0] = string.char(math.random(65, 90))
              _len_0 = _len_0 + 1
            end
            return _accum_0
          end)())
          path = fs.combine(state.dir, name)
        end
        state.current_task = self:_add_task((function()
          if state.connection.id ~= nil then
            state.connection.socket = connect(os.computerID(), self.modem, state.connection.id, self.connection.port, 1)
          end
          if state.connection.socket == nil then
            if state.connection.task ~= nil then
              self.tasks[state.connection.task] = nil
            end
            state.connection = nil
            state.socket:send("425 Unable to open data connection.")
          end
          local data = state:receive_data(self.port_provider)
          local fp
          if state.transfer_params.type == "A" then
            fp = self.filesystem.open(path, "w")
          else
            fp = self.filesystem.open(path, "wb")
          end
          local _ = fp.write
          fp.close()
          state.socket:send("250 Transfer complete: " .. name)
          state.connection = nil
          state.current_task = nil
          state.status.current_bytes = nil
          state.status.target_bytes = nil
          state.status.current_command = nil
        end), "store unique " .. path)
        state.status.current_command = "STOU " .. path
        if state.connection.socket == nil then
          return "150 Opening data connection"
        else
          return "125 Data connection already open; transfer starting."
        end
      end,
      APPE = function(self, state, file)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if file == nil then
          return "501 Missing file name"
        end
        if state.connection.port == nil then
          return "503 Bad sequence of commands"
        end
        if state.current_task ~= nil then
          return "425 Data connection already open"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        if self.filesystem.isDir(path) then
          state.connection = nil
          return "550 Path is directory"
        end
        state.current_task = self:_add_task((function()
          if state.connection.id ~= nil then
            state.connection.socket = connect(os.computerID(), self.modem, state.connection.id, self.connection.port, 1)
          end
          if state.connection.socket == nil then
            if state.connection.task ~= nil then
              self.tasks[state.connection.task] = nil
            end
            state.connection = nil
            state.socket:send("425 Unable to open data connection.")
          end
          local data = state:receive_data(self.port_provider)
          local fp
          if state.transfer_params.type == "A" then
            fp = self.filesystem.open(path, "a")
          else
            fp = self.filesystem.open(path, "ab")
          end
          fp.write(data)
          fp.close()
          state.socket:send("250 Transfer complete")
          state.connection = nil
          state.current_task = nil
          state.status.current_bytes = nil
          state.status.target_bytes = nil
          state.status.current_command = nil
        end), "append " .. file)
        state.status.current_command = "APPE " .. path
        if state.connection.socket == nil then
          return "150 Opening data connection"
        else
          return "125 Data connection already open; transfer starting."
        end
      end,
      ALLO = function(self, state)
        return "502 ALLO command not implemented"
      end,
      REST = function(self, state)
        return "502 REST command not implemented"
      end,
      RNFR = function(self, state, name)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if name == nil then
          return "501 Missing file name"
        end
        state.rename_from = name
        return "350 Awaiting name to rename to."
      end,
      RNTO = function(self, state, name)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if name == nil then
          return "501 Missing file name"
        end
        if state.rename_from == nil then
          return "503 Bad sequence of commands"
        end
        local old
        if state.rename_from:sub(1, 1) == "/" then
          old = state.rename_from
        else
          old = fs.combine(state.dir, state.rename_from)
        end
        local new
        if name:sub(1, 1) == "/" then
          new = name
        else
          new = fs.combine(state.dir, name)
        end
        self.filesystem.move(old, new)
        state.rename_from = nil
        return "250 File operation succeeded"
      end,
      ABOR = function(self, state)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if self.current_task == nil then
          return "226 No data transfer in progress"
        end
        self.tasks[state.current_task] = nil
        state.socket:send("426 Data transfer aborted.")
        return "226 Data transfer successfully aborted."
      end,
      DELE = function(self, state, file)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if file == nil then
          return "501 Missing file name"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        if not fs.exists(path) then
          return "550 File not found"
        end
        if fs.isDir(path) then
          return "550 Path is directory"
        end
        self.filesystem.delete(path)
        return "250 File deleted"
      end,
      RMD = function(self, state, file)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if file == nil then
          return "501 Missing file name"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        if not fs.exists(path) then
          return "550 Directory not found"
        end
        if not fs.isDir(path) then
          return "550 Path is not directory"
        end
        self.filesystem.delete(path)
        return "250 Directory deleted"
      end,
      MKD = function(self, state, file)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if file == nil then
          return "501 Missing file name"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        self.filesystem.makeDir(path)
        return '257 Created directory "' .. path .. '"'
      end,
      PWD = function(self, state)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        return '257 "' .. self.dir .. '"'
      end,
      LIST = function(self, state, file)
        if file == nil then
          file = state.dir
        end
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        return "202 Not implemented yet"
      end,
      NLST = function(self, state, file)
        if file == nil then
          file = state.dir
        end
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        if state.connection.port == nil then
          return "503 Bad sequence of commands"
        end
        if state.current_task ~= nil then
          return "425 Data connection already open"
        end
        local path
        if file:sub(1, 1) == "/" then
          path = file
        else
          path = fs.combine(state.dir, file)
        end
        if not self.filesystem.isDir(path) then
          state.connection = nil
          return "550 Path is not a directory"
        end
        state.current_task = self:_add_task((function()
          if state.connection.id ~= nil then
            state.connection.socket = connect(os.computerID(), self.modem, state.connection.id, self.connection.port, 1)
          end
          if state.connection.socket == nil then
            if state.connection.task ~= nil then
              self.tasks[state.connection.task] = nil
            end
            state.connection = nil
            state.socket:send("425 Unable to open data connection.")
          end
          state:send_data(table.concat((function()
            local _accum_0 = { }
            local _len_0 = 1
            for _, v in ipairs(self.filesystem.list(path)) do
              _accum_0[_len_0] = v
              _len_0 = _len_0 + 1
            end
            return _accum_0
          end)(), "\n"), self.port_provider)
          state.connection = nil
          state.current_task = nil
          state.status.current_bytes = nil
          state.status.target_bytes = nil
          state.status.current_command = nil
        end), "name list " .. file)
        state.status.current_command = "NLST " .. path
        if state.connection.socket == nil then
          return "150 Opening data connection"
        else
          return "125 Data connection already open; transfer starting."
        end
      end,
      SITE = function(self, state)
        return "202 Not implemented"
      end,
      SYST = function(self, state)
        return "215 UNKNOWN CraftOS"
      end,
      STAT = function(self, state)
        if self.auth ~= nil and not self.auth(state.username, state.password) then
          return "530 Not logged in."
        end
        return "211-Status of '" .. tostring(os.computerLabel()) .. "'\n Connected from ID " .. tostring(state.socket.id) .. "\n Logged in as " .. tostring(state.username) .. "\n TYPE: " .. tostring(state.transfer.params == "A" and "ASCII" or "Image") .. ", STRUcture: File, Mode: " .. tostring(state.transfer.params == "S" and "Stream" or (state.transfer.params == "B" and "Block" or "Compressed")) .. "\n Total bytes transferred for session: " .. tostring(state.status.total_bytes) .. "\n" .. (self.current_task == nil and "No data connection" or tostring(state.connection.id == nil and "Passive" or "Active") .. " data transfer from " .. tostring(state.connection.socket.id) .. " port " .. tostring(state.connection.port) .. "\n" .. tostring(state.status.current_command) .. " (" .. tostring(state.status.target_bytes) .. "/" .. tostring(state.status.current_bytes) .. ")") .. "\n211 End of status"
      end,
      HELP = function(self, state, cmd)
        return "202 Not implemented (yet)"
      end,
      NOOP = function(self, state)
        return "200 NOOP command successful"
      end
    },
    _add_task = function(self, func, name)
      if self.tasks == nil then
        return 
      end
      local id = #self.tasks + 1
      self.tasks[id] = {
        coro = coroutine.create(func),
        filter = nil,
        _name = name
      }
      return id
    end,
    _listen = function(self)
      while true do
        local socket = listen(os.computerID(), self.modem, self.port)
        self:_add_task((function()
          return self:_run_connection(server_connection(socket))
        end), "connection " .. socket.id)
      end
    end,
    _run_connection = function(self, state)
      state.socket:send("220 Hello!")
      while state.socket.is_open do
        local req, err = state.socket:receive(3600)
        if req == nil then
          break
        end
        local command, arg = req
        if req:find(" ") then
          command, arg = req:sub(1, req:find(" ") - 1):upper(), req:sub(req:find(" ") + 1)
        end
        if self.commands[command] == nil then
          state.socket:send("500 Unknown command '" .. command .. "'")
        else
          if arg == "" then
            arg = nil
          end
          local reply = self.commands[command](self, state, arg)
          if not (state.socket.is_open) then
            break
          end
          if self.commands[command] ~= nil then
            state.socket:send(reply)
          end
        end
      end
      return state.socket:close()
    end,
    listen = function(self)
      self.tasks = {
        {
          coro = coroutine.create(function()
            return self:_listen()
          end),
          filter = nil,
          _name = "root listener"
        }
      }
      while #self.tasks > 0 do
        local ev = {
          os.pullEvent()
        }
        local delete = { }
        for i, v in ipairs(self.tasks) do
          if v.filter == nil or v.filter == ev[1] then
            local ok
            ok, v.filter = coroutine.resume(v.coro, table.unpack(ev))
            if not ok then
              print((v.name or "unknown") .. ": " .. v.filter)
            end
            if not ok or coroutine.status(v.coro) ~= "suspended" then
              table.insert(delete, i)
            end
          end
        end
        for _, i in ipairs(delete) do
          self.tasks[i] = nil
        end
      end
      self.tasks = nil
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, modem, port, auth, filesystem, port_provider)
      if port == nil then
        port = 21
      end
      if auth == nil then
        auth = nil
      end
      if filesystem == nil then
        filesystem = fs
      end
      if port_provider == nil then
        port_provider = createPortProvider(modem)
      end
      self.modem = modem
      self.port = port
      self.auth = auth
      self.filesystem = filesystem
      self.port_provider = port_provider
      return self.modem.open(self.port)
    end,
    __base = _base_0,
    __name = "server"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  server = _class_0
end
return {
  client = client,
  server = server
}
