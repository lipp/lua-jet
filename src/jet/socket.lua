local ev = require'ev'
local socket = require'socket'
require'pack'-- blends pack/unpack into string table

local print = print
local pairs = pairs
local tinsert = table.insert
local tconcat = table.concat
local ipairs = ipairs
local assert = assert
local spack = string.pack
local sunpack = string.unpack
local error = error
local pcall = pcall
local type = type
local eps = 2^-40

local wrap_sync = function(sock)
  assert(sock)
  local wrapped = {}
  sock:setoption('tcp-nodelay',true)
  wrapped.send = function(_,message)
    sock:send(spack('>I',#message))
    sock:send(message)
  end
  wrapped.receive = function(_)
    local bin_len = sock:receive(4)
    local _,len = bin_len:unpack('>I')
    return sock:receive(len)
  end
  return wrapped
end

local wrap = function(sock,args)
  assert(sock)
  args = args or {}
  -- set non blocking
  sock:settimeout(0)
  -- send message asap
  sock:setoption('tcp-nodelay',true)
  -- enable keep alive for detecting broken connections
  sock:setoption('keepalive',true)
  local on_message = args.on_message or function() end
  local on_close = args.on_close or function() end
  local on_error = args.on_error or function() end
  local loop = args.loop or ev.Loop.default
  local send_buffer = ''
  local wrapped = {}
  local read_io
  local send_io
  
  local detach = function(f)
    if ev.Idle then
      ev.Idle.new(function(loop,io)
          io:stop(loop)
          f()
        end):start(loop)
    else
      ev.Timer.new(function(loop,io)
          io:stop(loop)
          f()
        end,eps):start(loop)
    end
  end
  
  local handle_error = function(io_active,err_msg)
    read_io:stop(loop)
    read_io:clear_pending(loop)
    send_io:stop(loop)
    send_io:clear_pending(loop)
    sock:close()
    if io_active then
      on_error(wrapped,err_msg)
      on_close(wrapped)
    else
      detach(function()
          on_error(wrapped,err_msg)
          on_close(wrapped)
        end)
    end
  end
  
  local handle_close = function(io_active)
    read_io:stop(loop)
    read_io:clear_pending(loop)
    send_io:stop(loop)
    send_io:clear_pending(loop)
    sock:close()
    if io_active then
      on_close(wrapped)
    else
      detach(function()
          on_close(wrapped)
        end)
    end
  end
  
  local send_pos
  local send_message = function(loop,write_io)
    local sent,err,sent_so_far = sock:send(send_buffer,send_pos)
    if not sent and err ~= 'timeout' then
      local io_active = write_io:is_active()
      if err == 'closed' then
        handle_close(io_active)
      else
        handle_error(io_active,err)
      end
    elseif sent then
      send_pos = nil
      send_buffer = ''
      write_io:stop(loop)
    else
      send_pos = sent_so_far + 1
    end
  end
  local fd = sock:getfd()
  assert(fd > -1)
  send_io = ev.IO.new(send_message,fd,ev.WRITE)
  
  -- sends asynchronous the supplied message object
  --
  -- the message format is 32bit big endian integer
  -- denoting the size of the JSON following
  wrapped.send = function(_,message)
    send_buffer = send_buffer..spack('>I',#message)..message
    if not send_io:is_active() then
      send_message(loop,send_io)
      if send_buffer ~= '' then
        send_io:start(loop)
      end
    end
  end
  
  wrapped.close = function()
    wrapped.read_io():stop(loop)
    send_io:stop(loop)
    sock:shutdown()
    sock:close()
  end
  
  wrapped.on_message = function(_,f)
    assert(type(f) == 'function')
    on_message = f
  end
  
  wrapped.on_close = function(_,f)
    assert(type(f) == 'function')
    on_close = f
  end
  
  wrapped.on_error = function(_,f)
    assert(type(f) == 'function')
    on_error = f
  end
  
  wrapped.read_io = function()
    return read_io
  end
  
  local len
  local len_bin
  local message
  local _
  
  local receive_message = function(loop,read_io)
    local io_active = read_io:is_active()
    while true do
      if not len_bin or #len_bin < 4 then
        local err,sub
        len_bin,err,sub = sock:receive(4,len_bin)
        if len_bin then
          _,len = sunpack(len_bin,'>I')
        elseif err == 'timeout' then
          len_bin = sub
          return
        elseif err == 'closed' then
          handle_close(io_active)
          return
        else
          handle_error(io_active,'jet.socket receive failed with: '..err)
          return
        end
      end
      if len then
        -- 10 MB is limit
        if len > 10000000 then
          handle_error(io_active,'jet.socket message too big: '..len..' bytes')
          return
        end
        message,err,sub = sock:receive(len,message)
        if message then
          on_message(wrapped,message)
          len = nil
          len_bin = nil
          message = nil
        elseif err == 'timeout' then
          message = sub
          return
        elseif err == 'closed' then
          handle_close(io_active)
          return
        else
          handle_error(io_active,err)
          return
        end
      end
    end
  end
  
  read_io = ev.IO.new(receive_message,sock:getfd(),ev.READ)
  
  return wrapped
end

local mod = {
  wrap = wrap,
  wrap_sync = wrap_sync
}

return mod

