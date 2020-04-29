local crc32 = require("crc32")
local padstr
padstr = function(str, size)
  if #str < size then
    return str .. (" "):rep(size - str)
  else
    return str:sub(1, size)
  end
end
if false then
  return {
    connect = function(me, modem, id, port)
      local w = http.websocket("ws://localhost:" .. port)
      return setmetatable({
        send = function(self, s)
          return w.send(s) or true
        end,
        receive = function(self)
          return w.receive()
        end,
        close = function(self)
          return w.close()
        end
      }, {
        __index = function(self, t)
          if t == "is_open" then
            return w.isOpen()
          end
        end
      })
    end
  }
end
local socket
do
  local _class_0
  local _base_0 = {
    send = function(self, data)
      if data ~= nil and type(data) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(data) .. ")", 2)
      end
      if not (self.is_open) then
        return false
      end
      if not self.is_open then
        self.modem.open(self.port)
      end
      local tm
      if self.timeout == 0 then
        tm = nil
      else
        tm = os.startTimer(self.timeout)
      end
      self.modem.transmit(self.port, self.port, {
        from = self.me,
        to = self.id,
        type = "message",
        size = #data,
        data = data
      })
      while true do
        if not self.is_open then
          self.modem.open(self.port)
        end
        local ev = {
          os.pullEvent()
        }
        if ev[1] == "timer" and ev[2] == tm then
          return false, "Timeout"
        elseif ev[1] == "modem_message" and ev[3] == self.port and ev[4] == self.port and (type(ev[5]) == "table") then
          do
            ev[5].to = self.me and ev[5].from == self.id
            if ev[5].to then
              local _exp_0 = ev[5].type
              if "received" == _exp_0 then
                if self.timeout > 0 then
                  os.cancelTimer(tm)
                end
                return tonumber(padstr(ev[5].data, ev[5].size)) == crc32(data), "Invalid checksum"
              elseif "disconnected" == _exp_0 then
                self:close()
                if self.timeout > 0 then
                  os.cancelTimer(tm)
                end
                return false, (ev[5].size > 0 and padstr(ev[5].data, ev[5].size or "Socket closed"))
              end
            end
          end
        end
      end
    end,
    receive = function(self, timeout)
      if timeout == nil then
        timeout = self.timeout
      end
      if not (self.is_open) then
        return nil, "Socket closed"
      end
      if type(timeout) ~= "number" then
        error("bad argument #1 (expected number, got " .. type(timeout) .. ")", 2)
      end
      if not self.is_open then
        self.modem.open(self.port)
      end
      local tm
      if timeout == 0 then
        tm = nil
      else
        tm = os.startTimer(timeout)
      end
      while true do
        if not self.is_open then
          self.modem.open(self.port)
        end
        local ev = {
          os.pullEvent()
        }
        if not (self.is_open) then
          if timeout > 0 then
            os.cancelTimer(tm)
          end
          return nil, "Socket closed"
        end
        if ev[1] == "timer" and ev[2] == tm then
          return nil, "Timeout"
        elseif ev[1] == "modem_message" and ev[3] == self.port and ev[4] == self.port and type(ev[5]) == "table" then
          do
            ev[5].to = self.me and ev[5].from == self.id
            if ev[5].to then
              local _exp_0 = ev[5].type
              if "message" == _exp_0 then
                self.modem.transmit(self.port, self.port, {
                  from = self.me,
                  to = self.id,
                  type = "received",
                  size = 8,
                  data = ("%08X"):format(crc32(padstr(ev[5].data, ev[5].size)))
                })
                if timeout > 0 then
                  os.cancelTimer(tm)
                end
                return padstr(ev[5].data, ev[5].size)
              elseif "disconnected" == _exp_0 then
                self:close()
                if timeout > 0 then
                  os.cancelTimer(tm)
                end
                return nil, (function()
                  if ev[5].size > 0 then
                    return padstr(ev[5].data, ev[5].size)
                  else
                    return "Socket closed"
                  end
                end)()
              end
            end
          end
        end
      end
    end,
    close = function(self, reason)
      if reason ~= nil and type(reason) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(reason) .. ")", 2)
      end
      if not (self.is_open) then
        return 
      end
      self.modem.transmit(self.port, self.port, {
        from = self.me,
        to = self.id,
        type = "disconnected",
        size = (function()
          if reason then
            return #reason
          else
            return 0, {
              data = reason or ""
            }
          end
        end)()
      })
      self.modem.close(self.port)
      self.is_open = false
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, me, modem, id, port, timeout)
      self.me = me
      self.modem = modem
      self.id = id
      self.port = port
      self.timeout = timeout
      self.is_open = true
      self.message_queue = { }
    end,
    __base = _base_0,
    __name = "socket"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  socket = _class_0
end
local connect
connect = function(me, modem, id, port, timeout)
  if timeout == nil then
    timeout = 5
  end
  if type(modem) ~= "table" then
    error("bad argument #2 (expected modem (table), got " .. type(modem) .. ")", 2)
  elseif type(modem.open) ~= "function" or type(modem.transmit) ~= "function" or type(modem.close) ~= "function" then
    error("bad argument #2 (expected modem, got non-modem table)", 2)
  end
  if type(port) ~= "number" then
    error("bad argument #4 (expected number, got " .. type(port) .. ")", 2)
  elseif port < 0 or port > 65535 then
    error("bad argument #4 (port out of range: " .. port .. ")", 2)
  end
  if type(timeout) ~= "number" then
    error("bad argument #5 (expected number, got " .. type(timeout) .. ")", 2)
  end
  if me == id then
    error("attempted to connect to self", 2)
  end
  modem.open(port)
  modem.transmit(port, port, {
    from = me,
    to = id,
    type = "connect",
    size = 0,
    data = ""
  })
  local tm = os.startTimer(timeout)
  while true do
    local ev = {
      os.pullEvent()
    }
    if ev[1] == "timer" and ev[2] == tm then
      modem.close(port)
      return nil, "Timeout"
    elseif ev[1] == "modem_message" and ev[3] == port and ev[4] == port and type(ev[5]) == "table" and ev[5].from == id and ev[5].to == me then
      if ev[5].type == "connected" then
        return socket(me, modem, id, port, timeout)
      elseif ev[5].type == "disconnected" or ev[5].type == "error" then
        modem.close(port)
        return nil, padstr(ev[5].data, ev[5].size)
      end
    end
  end
end
local listen
listen = function(me, modem, port, timeout)
  if timeout == nil then
    timeout = 5
  end
  if type(modem) ~= "table" then
    error("bad argument #2 (expected modem (table), got " .. type(modem) .. ")", 2)
  elseif type(modem.open) ~= "function" or type(modem.transmit) ~= "function" or type(modem.close) ~= "function" then
    error("bad argument #2 (expected modem, got non-modem table)", 2)
  end
  if type(port) ~= "number" then
    error("bad argument #3 (expected number, got " .. type(port) .. ")", 2)
  elseif port < 0 or port > 65535 then
    error("bad argument #3 (port out of range: " .. port .. ")", 2)
  end
  if type(timeout) ~= "number" then
    error("bad argument #4 (expected number, got " .. type(timeout) .. ")", 2)
  end
  modem.open(port)
  while true do
    local ev = {
      os.pullEvent("modem_message")
    }
    if ev[3] == port and ev[4] == port and type(ev[5]) == "table" and ev[5].to == me and ev[5].type == "connect" then
      modem.transmit(port, port, {
        from = me,
        to = ev[5].from,
        type = "connected",
        size = 0,
        data = ""
      })
      return socket(me, modem, ev[5].from, port, timeout)
    end
  end
end
return {
  connect = connect,
  listen = listen
}
