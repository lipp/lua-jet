local ev = require'ev'
local socket = require'socket'
require'pack'-- blends pack/unpack into string table

local tinsert = table.insert
local tconcat = table.concat
local spack = string.pack
local sunpack = string.unpack
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
  local on_open = args.on_open or function() end
  local on_close = args.on_close or function() end
  local on_error = args.on_error or function() end
  local loop = args.loop or ev.Loop.default
  local send_buffer = ''
  local wrapped = {}
  local read_io
  local send_io
  local connect_io
  local connected = sock:getpeername()
  
  local stop_ios = function()
    if connect_io then
      connect_io:stop(loop)
      connect_io:clear_pending(loop)
    end
    read_io:stop(loop)
    read_io:clear_pending(loop)
    send_io:stop(loop)
    send_io:clear_pending(loop)
  end
  
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
    stop_ios()
    sock:close()
    if io_active then
      on_error(wrapped,err_msg)
      on_close(wrapped)
      on_close = function() end
    else
      detach(function()
          on_error(wrapped,err_msg)
          on_close(wrapped)
          on_close = function() end
        end)
    end
  end
  
  local handle_close = function(io_active)
    stop_ios()
    sock:close()
    if io_active then
      on_close(wrapped)
      on_close = function() end
    else
      detach(function()
          on_close(wrapped)
          on_close = function() end
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
  
  local flush = function()
    if not send_io:is_active() then
      send_message(loop,send_io)
      if send_buffer ~= '' then
        send_io:start(loop)
      end
    end
  end
  
  -- sends asynchronous the supplied message object
  --
  -- the message format is 32bit big endian integer
  -- denoting the size of the JSON following
  wrapped.send = function(_,message)
    send_buffer = send_buffer..spack('>I',#message)..message
    if connected then
      flush()
    end
  end
  
  local closing
  
  wrapped.close = function()
    sock:close()
    if not closing then
      closing = true
      stop_ios()
      if connected then
        sock:shutdown()
        connected = false
      end
      detach(function()
          on_close(wrapped)
          on_close = function() end
        end)
    end
  end
  
  wrapped.connect = function()
    detach(function()
        local sock_connected,err = sock:connect(args.ip,args.port)
        if sock_connected or err == 'already connected' then
          connected = true
          flush()
          read_io:start(loop)
          on_open(wrapped)
        elseif err == 'timeout' or err == 'Operation already in progress' then
          connect_io = ev.IO.new(
            function(loop,io)
              io:stop(loop)
              connected = true
              flush()
              read_io:start(loop)
              connect_io = nil
              on_open(wrapped)
            end,sock:getfd(),ev.WRITE)
          connect_io:start(loop)
        else
          on_error('jet.socket:connect() failed: '..err)
        end
      end)
  end
  
  wrapped.on_message = function(_,f)
    assert(type(f) == 'function')
    on_message = f
  end
  
  wrapped.on_open = function(_,f)
    assert(type(f) == 'function')
    on_open = f
  end
  
  wrapped.on_close = function(_,f)
    assert(type(f) == 'function')
    on_close = f
  end
  
  wrapped.on_error = function(_,f)
    assert(type(f) == 'function')
    on_error = f
  end
  
  local len
  local len_bin
  local message
  local _
  
  local receive_message = function(loop,read_io)
    local io_active = read_io:is_active()
    while true do
      local err,sub
      if not len_bin or #len_bin < 4 then
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
  
  if connected then
    read_io:start(loop)
  end
  
  return wrapped
end

local new = function(args)
  assert(args.ip,'ip required')
  local sock
  if socket.dns and socket.dns.getaddrinfo then
    local addrinfo,err = socket.dns.getaddrinfo(args.ip)
    if addrinfo then
      assert(#addrinfo > 0)
      if addrinfo[1].family == 'inet6' then
        sock = socket.tcp6()
      else
        sock = socket.tcp()
      end
    else
      assert(err,'error message expected')
      error(err)
    end
  else
    sock = socket.tcp()
  end
  return wrap(sock,args)
end

--- creates and binds a listening socket for
-- ipv4 and (if available) ipv6.
local sbind = function(host,port)
  if socket.tcp6 then
    local server = socket.tcp6()
    assert(server:setoption('ipv6-v6only',false))
    assert(server:setoption('reuseaddr',true))
    assert(server:bind(host,port))
    assert(server:listen())
    return server
  else
    return socket.bind(host,port)
  end
end

local listener = function(config)
  local loop = config.loop or ev.Loop.default
  local log = config.log or function() end
  local lsock,err = sbind('*',config.port)
  if not lsock then
    error(err)
  end
  local accept = function()
    local sock = lsock:accept()
    if not sock then
      log('accepting peer failed')
      return
    end
    local jsock = wrap(sock,{loop = config.loop})
    config.on_connect(jsock)
  end
  lsock:settimeout(0)
  local listen_io = ev.IO.new(
    accept,
    lsock:getfd(),
  ev.READ)
  listen_io:start(loop)
  
  local l = {}
  l.close = function()
    listen_io:stop(loop)
    lsock:close()
  end
  return l
end

local mod = {
  wrap = wrap,
  new = new,
  wrap_sync = wrap_sync,
  listener = listener,
}

return mod
