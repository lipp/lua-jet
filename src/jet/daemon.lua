local cjson = require'cjson'
local ev = require'ev'
local socket = require'socket'
local jsocket = require'jet.socket'
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local tsort = table.sort
local print = print
local pairs = pairs
local ipairs = ipairs
local assert = assert
local pcall = pcall
local type = type
local error = error
local require = require
local tostring = tostring
local jencode = cjson.encode
local jdecode = cjson.decode
local jnull = cjson.null

module('jet.daemon')

local log = function(...)
  print('jetd',...)
end

local info = function(...)
  log('info',...)
end

local crit = function(...)
  log('err',...)
end

local debug = function(...)
  log('debug',...)
end

local invalid_params = function(data)
  local err = {
    code = -32602,
    message = 'Invalid params',
    data = data
  }
  return err
end


local create_daemon = function(options)
  -- holds all (jet.socket.wrapped) clients index by client itself
  local clients = {}
  local states = {}
  local leaves = {}
  local routes = {}
  
  local route_message = function(client,message)
    local route = routes[message.id]
    if route then
      routes[message.id] = nil
      message.id = route.id
      route.receiver:queue(message)
    else
      log('unknown route id:',jencode(message))
    end
  end
  
  local publish = function(notification)
    for client in pairs(clients) do
      for fetch_id,fetcher in pairs(client.fetchers) do
        local ok,err = pcall(fetcher,notification)
        if not ok then
          crit('publish failed',fetch_id,err)
        end
      end
    end
  end
  
  local flush_clients = function()
    for client in pairs(clients) do
      client:flush()
    end
  end
  
  local create_path_matcher = function(options)
    local unmatch = options.unmatch
    local match = options.match
    if not unmatch and match and #match == 1 then
      local match = match[1]
      return function(path)
        return path:match(match)
      end
    elseif type(match) == 'table' and type(unmatch) == 'table' then
      return function(path)
        for _,unmatch in ipairs(unmatch) do
          if path:match(unmatch) then
            return false
          end
        end
        for _,match in ipairs(match) do
          if path:match(match) then
            return true
          end
        end
      end
    elseif type(match) == 'table' then
      return function(path)
        for _,match in ipairs(match) do
          if path:match(match) then
            return true
          end
        end
      end
    else
      return nil
    end
  end
  
  local create_value_matcher = function(options)
    if options.equals ~= nil then
      local equals = options.equals
      return function(value)
        return value == equals
      end
    end
    return nil
  end
  
  local create_fetcher_with_deps = function(options,notify)
    local path_matcher = create_path_matcher(options)
    local value_matcher = create_value_matcher(options)
    local added = {}
    local contexts = {}
    local deps = {}
    local ok = {}
    local fetchop = function(notification)
      local path = notification.path
      local value = notification.value
      local backrefs = {path_matcher(path)}
      local context = contexts[path]
      if #backrefs > 0 then
        if not context then
          context = {}
          context.path = path
          context.value_ok = (value_matcher and value_matcher(value)) or true
          context.deps_ok = {}
          for i,dep in ipairs(options.deps) do
            local dep_path = dep.path:gsub('\\(%d)',function(index)
                index = tonumber(index)
                return assert(backrefs[index])
              end)
            if not deps[dep_path] then
              deps[dep_path] = {
                value_matcher = create_value_matcher(dep),
                context = context
              }
              context.deps_ok[dep_path] = false
            end
          end
          contexts[path] = context
        else
          context.value_ok = (value_matcher and value_matcher(value)) or true
        end
        context.value = value
      elseif deps[path] then
        local dep = deps[path]
        context = dep.context
        context.deps_ok[path] = dep.value_matcher(value) or false
      end
      
      local all_ok = false
      if context.value_ok then
        all_ok = true
        for _,dep_ok in pairs(context.deps_ok) do
          if not dep_ok then
            all_ok = false
            break
          end
        end
      end
      local relevant_path = context.path
      local is_added = added[relevant_path]
      local event
      if not all_ok then
        if is_added then
          event = 'remove'
          added[relevant_path] = nil
        else
          return
        end
      elseif all_ok then
        if is_added then
          event = 'change'
        else
          event = 'add'
          added[relevant_path] = true
        end
      end
      
      notify
      {
        path = relevant_path,
        event = event,
        value = context.value
      }
    end
    
    return fetchop
  end
  
  local create_fetcher_without_deps = function(options,notify)
    local path_matcher = create_path_matcher(options)
    local value_matcher = create_value_matcher(options)
    local added = {}
    local fetchop = function(notification)
      local path = notification.path
      local value = notification.value
      local is_added = added[path]
      if (path_matcher and not path_matcher(path)) or
      (value_matcher and not value_matcher(value)) or
      notification.event == 'remove' then
        if is_added then
          added[path] = nil
          notify
          {
            path = path,
            event = 'remove',
            value = value
          }
        end
        return
      end
      local event
      if not is_added then
        event = 'add'
        added[path] = true
      else
        event = 'change'
      end
      notify
      {
        path = path,
        event = event,
        value = value
      }
    end
    
    return fetchop
  end
  
  local create_fetcher = function(options,notify)
    if options.deps and #options.deps > 0 then
      return create_fetcher_with_deps(options,notify)
    else
      return create_fetcher_without_deps(options,notify)
    end
  end
  
  local checked = function(params,key,typename)
    local p = params[key]
    if p ~= nil then
      if typename then
        if type(p) == typename then
          return p
        else
          error(invalid_params{wrong_type=key,got=params})
        end
      else
        return p
      end
    else
      error(invalid_params{missing_param=key,got=params})
    end
  end
  
  local optional = function(params,key,typename)
    local p = params[key]
    if p then
      if typename then
        if type(p) == typename then
          return p
        else
          error(invalid_params{wrong_type=key,got=params})
        end
      else
        return p
      end
    end
  end
  
  local change = function(client,message)
    local notification = message.params
    local path = checked(notification,'path','string')
    local leave = leaves[path]
    if leave then
      leave.value = notification.value
      notification.event = 'change'
      publish(notification)
    else
      local error = invalid_params{invalid_path=path}
      if message.id then
        client:queue
        {
          id = message.id,
          error = error
        }
      else
        log('post failed',jencode(message))
      end
    end
  end
  
  local fetch = function(client,message)
    local params = message.params
    local fetch_id = checked(params,'id','string')
    local notify = function(nparams)
      client:queue
      {
        method = fetch_id,
        params = nparams
      }
    end
    local params_ok,fetcher = pcall(create_fetcher,params,notify)
    if not params_ok then
      error(invalid_params{fetchParams = params, reason = fetcher})
    end
    
    for path,leave in pairs(leaves) do
      fetcher
      {
        path = path,
        value = leave.value,
        event = 'add'
      }
    end
    
    client.fetchers[fetch_id] = fetcher
    if message.id then
      client:queue
      {
        id = message.id,
        result = {}
      }
    end
  end
  
  local route = function(client,message)
    local params = message.params
    local path = checked(params,'path','string')
    local leave = leaves[path]
    if leave then
      local id
      if message.id then
        id = message.id..tostring(client)
        assert(not routes[id])
        -- save route to forward reply
        routes[id] = {
          receiver = client,
          id = message.id
        }
      end
      local req = {
        id = id,-- maybe nil
        method = path
      }
      
      local value = params.value
      if value then
        req.params = {value = value}
      else
        req.params = params.args
      end
      leave.client:queue(req)
    else
      local error = invalid_params{notExists=path}
      if message.id then
        client:queue
        {
          id = message.id,
          error = error
        }
      end
      log('route failed',jencode(error))
    end
  end
  
  local add = function(client,message)
    local params = message.params
    local path = checked(params,'path','string')
    if leaves[path] then
      error(invalid_params{exists = path})
    end
    local value = params.value-- might be nil for actions / methods
    local leave = {
      client = client,
      value = value
    }
    leaves[path] = leave
    publish
    {
      path = path,
      event = 'add',
      value = value
    }
  end
  
  local remove = function(client,message)
    local params = message.params
    local path = checked(params,'path','string')
    if not leaves[path] then
      error(invalid_params{invalid_path = path})
    end
    local leave = assert(leaves[path])
    leaves[path] = nil
    publish
    {
      path = path,
      event = 'remove',
      value = leave.value
    }
  end
  
  local sync = function(f)
    local sc = function(client,message)
      local ok,result = pcall(f,client,message)
      if message.id then
        if ok then
          client:queue
          {
            id = message.id,
            result = result or {}
          }
        else
          local error
          if type(result) == 'table' and result.code and result.message then
            error = result
          else
            error = {
              code = -32603,
              message = 'Internal error',
              data = result
            }
          end
          client:queue
          {
            id = message.id,
            error = error
          }
        end
      elseif not ok then
        log('sync '..message.method..' failed',jencode(result))
      end
    end
    return sc
  end
  
  local async = function(f)
    local ac = function(client,message)
      local ok,err = pcall(f,client,message)
      if message.id then
        if not ok then
          local error
          if type(err) == 'table' and err.code and err.message then
            error = err
          else
            error = {
              code = -32603,
              message = 'Internal error',
              data = err
            }
          end
          client:queue
          {
            id = message.id,
            error = err
          }
        end
      elseif not ok then
        log('async '..message.method..' failed:',jencode(err))
      end
    end
    return ac
  end
  
  local services = {
    add = sync(add),
    remove = sync(remove),
    call = async(route),
    set = async(route),
    fetch = async(fetch),
    change = sync(change),
    echo = sync(function(client,message)
        return message.params
      end)
  }
  
  local dispatch_request = function(client,message)
    local error
    assert(message.method)
    local service = services[message.method]
    if service then
      local ok,err = pcall(service,client,message)
      if ok then
        return
      else
        if type(err) == 'table' and err.code and err.message then
          error = err
        else
          error = {
            code = -32603,
            message = 'Internal error',
            data = err
          }
        end
      end
    else
      error = {
        code = -32601,
        message = 'Method not found',
        data = message.method
      }
    end
    client:queue
    {
      id = message.id,
      error = error
    }
  end
  
  local dispatch_notification = function(client,message)
    local service = services[message.method]
    if service then
      local ok,err = pcall(service,client,message)
      if not ok then
        log('dispatch_notification error:',jencode(err))
      end
    end
  end
  
  local dispatch_single_message = function(client,message)
    if message.id then
      if message.method then
        dispatch_request(client,message)
      elseif message.result or message.error then
        route_message(client,message)
      else
        client:queue
        {
          id = message.id,
          error = {
            code = -32600,
            message = 'Invalid Request',
            data = message
          }
        }
        log('message not dispatched:',jencode(message))
      end
    elseif message.method then
      dispatch_notification(client,message)
    else
      log('message not dispatched:',jencode(message))
    end
  end
  
  local dispatch_message = function(client,message,err)
    local ok,err = pcall(
      function()
        if message then
          if message == jnull then
            client:queue
            {
              error = {
                code = -32600,
                message = 'Invalid Request',
                data = 'message is null'
              }
            }
          elseif #message > 0 then
            for i,message in ipairs(message) do
              dispatch_single_message(client,message)
            end
          else
            dispatch_single_message(client,message)
          end
        else
          client:queue
          {
            error = {
              code  = -32700,
              messsage = 'Parse error'
            }
          }
        end
      end)
    if not ok then
      crit('dispatching message',jencode(message),err)
    end
    flush_clients()
  end
  
  local options = options or {}
  local port = options.port or 11122
  local loop = options.loop or ev.Loop.default
  
  local create_client = function(ops)
    local client = {}
    client.release = function()
      if client then
        client.fetchers = {}
        for path,leave in pairs(leaves) do
          if leave.client == client then
            publish
            {
              event = 'remove',
              path = path,
              value = leave.value
            }
            leaves[path] = nil
          end
        end
        flush_clients()
        ops.close()
        clients[client] = nil
        client = nil
      end
    end
    client.close = function(_)
      client:flush()
      ops.close()
    end
    client.queue = function(_,message)
      if not client.messages then
        client.messages = {}
      end
      tinsert(client.messages,message)
    end
    local send = ops.send
    client.flush = function(_)
      if client.messages then
        local num = #client.messages
        if num == 1 then
          send(client.messages[1])
        elseif num > 1 then
          send(client.messages)
        else
          assert(false,'messages must contain at least one element if not nil')
        end
        client.messages = nil
      end
    end
    client.fetchers = {}
    return client
  end
  
  local listener
  local accept_tcp = function(loop,accept_io)
    local sock = listener:accept()
    if not sock then
      log('accepting client failed')
      return
    end
    local jsock = jsocket.wrap(sock)
    local client = create_client
    {
      close = function() jsock:close() end,
      send = function(msg) jsock:send(msg) end
    }
    jsock:on_message(function(_,...)
        dispatch_message(client,...)
      end)
    jsock:on_close(function(_,...)
        client:release()
      end)
    jsock:on_error(function(_,...)
        err('socket error',...)
        client:release()
      end)
    jsock:read_io():start(loop)
    clients[client] = client
  end
  
  local accept_websocket = function(ws)
    local client = create_client
    {
      close = function()
        ws:close()
      end,
      send = function(msg)
        ws:send(jencode(msg))
      end,
    }
    ws:on_message(function(_,msg,opcode)
        if opcode == 1 then
          dispatch_message(client,jdecode(msg))
        end
      end)
    ws:on_close(function(_,...)
        client:release()
      end)
    ws:on_error(function(_,...)
        err('socket error',...)
        client:release()
      end)
    clients[client] = client
  end
  
  local listen_io
  local websocket_server
  
  local daemon = {
    start = function()
      listener = assert(socket.bind('*',port))
      listener:settimeout(0)
      listen_io = ev.IO.new(
        accept_tcp,
        listener:getfd(),
      ev.READ)
      listen_io:start(loop)
      
      if options.ws_port then
        local websocket_ok,err = pcall(function()
            websocket_server = require'websocket'.server.ev.listen
            {
              port = options.ws_port,
              protocols = {
                jet = accept_websocket
              }
            }
          end)
        if not websocket_ok then
          print('Could not start websocket server',err)
        end
      end
    end,
    stop = function()
      listen_io:stop(loop)
      listener:close()
      for _,client in pairs(clients) do
        client:close()
      end
      if websocket_server then
        websocket_server:close()
      end
    end
  }
  
  return daemon
end

return {
  new = create_daemon
}


