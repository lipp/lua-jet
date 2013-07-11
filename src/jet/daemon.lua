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
local tonumber = tonumber
local jencode = cjson.encode
local jdecode = cjson.decode
local jnull = cjson.null
local unpack = unpack
local mmin = math.min

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
  print = options.print or print
  
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
        local ok,refetch = pcall(fetcher,notification)
        if not ok then
          crit('publish failed',fetch_id,refetch)
        elseif refetch then
          for path,leave in pairs(leaves) do
            fetcher
            {
              path = path,
              value = leave.value,
              event = 'add'
            }
          end
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
    if not options.match and not options.unmatch and not options.equalsNot then
      return function()
        return true
      end
    end
    local unmatch = options.unmatch or {}
    local match = options.match or {}
    local equalsNot = options.equalsNot or {}
    local ci = options.caseInsensitive
    if ci then
      for i,unmat in ipairs(unmatch) do
        unmatch[i] = unmat:lower()
      end
      for i,mat in ipairs(match) do
        match[i] = mat:lower()
      end
      for i,eqnot in ipairs(equalsNot) do
        equalsNot[i] = eqnot:lower()
      end
    end
    return function(path)
      if ci then
        path = path:lower()
      end
      for _,unmatch in ipairs(unmatch) do
        if path:match(unmatch) then
          return false
        end
      end
      for _,eqnot in ipairs(equalsNot) do
        if eqnot == path then
          return false
        end
      end
      for _,match in ipairs(match) do
        local res = {path:match(match)}
        if #res > 0 then
          return true,res
        end
      end
      return false
    end
  end
  
  local create_value_matcher = function(options)
    local ops = {
      lessThan = function(a,b)
        return a < b
      end,
      greaterThan = function(a,b)
        return a > b
      end,
      equals = function(a,b)
        return a == b
      end,
      equalsNot = function(a,b)
        return a ~= b
      end
    }
    if options.where ~= nil then
      if #options.where > 1 then
        return function(value)
          local is_table = type(value) == 'table'
          for _,where in ipairs(options.where) do
            local need_table = where.prop and where.prop ~= ''
            if need_table and not is_table then
              return false
            end
            local op = ops[where.op]
            local comp
            if need_table then
              comp = value[where.prop]
            else
              comp = value
            end
            local ok,comp_ok = pcall(op,comp,where.value)
            if not ok or not comp_ok then
              return false
            end
          end
          return true
        end
      elseif options.where then
        if #options.where == 1 then
          options.where = options.where[1]
        end
        local where = options.where
        local op = ops[where.op]
        local ref = where.value
        if not where.prop or where.prop == '' then
          return function(value)
            local is_table = type(value) == 'table'
            if is_table then
              return false
            end
            local ok,comp_ok = pcall(op,value,ref)
            if not ok or not comp_ok then
              return false
            end
            return true
          end
        else
          return function(value)
            local is_table = type(value) == 'table'
            if not is_table then
              return false
            end
            local ok,comp_ok = pcall(op,value[where.prop],ref)
            if not ok or not comp_ok then
              return false
            end
            return true
          end
        end
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
      local match,backrefs = path_matcher(path)
      local context = contexts[path]
      if match and #backrefs > 0 then
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
              if leaves[dep_path] then
                context.deps_ok[dep_path] = deps[dep_path].value_matcher(leaves[dep_path].value)
              end
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
        local last = context.deps_ok[path]
        local new = false
        if dep.value_matcher then
          new = dep.value_matcher(value)
        end
        if last ~= new then
          context.deps_ok[path] = new
        else
          return
        end
      end
      
      if context then
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
    end
    return fetchop
  end
  
  local create_fetcher_without_deps = function(options,notify)
    local path_matcher = create_path_matcher(options)
    local value_matcher = create_value_matcher(options)
    local max = options.max
    local added = {}
    local n = 0
    
    local fetchop = function(notification)
      local path = notification.path
      local is_added = added[path]
      if not is_added and max and n == max then
        return
      end
      local path_matching = true
      if path_matcher and not path_matcher(path) then
        path_matching = false
      end
      local value_matching = true
      local value = notification.value
      if value_matcher and not value_matcher(value) then
        value_matching = false
      end
      local is_matching = false
      if path_matching and value_matching then
        is_matching = true
      end
      if not is_matching or notification.event == 'remove' then
        if is_added then
          added[path] = nil
          n = n - 1
          notify
          {
            path = path,
            event = 'remove',
            value = value
          }
          if max and n == (max-1) then
            return true
          end
        end
        return
      end
      local event
      if not is_added then
        event = 'add'
        added[path] = true
        n = n + 1
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
  
  local create_sorter = function(options,notify)
    if not options.sort then
      return nil
    end
    local from = options.sort.from or 1
    local to = options.sort.to or 10
    local matching = {}
    local sorted = {}
    
    local sort
    if not options.sort.byValue or options.sort.byPath then
      if options.sort.descending then
        sort = function(a,b)
          return a.path > b.path
        end
      else
        sort = function(a,b)
          return a.path < b.path
        end
      end
    elseif options.sort.byValue then
      local lt
      local gt
      if options.sort.prop then
        local prop = options.sort.prop
        lt = function(a,b)
          return a[prop] < b[prop]
        end
        gt = function(a,b)
          return a[prop] > b[prop]
        end
      else
        lt = function(a,b)
          return a < b
        end
        gt = function(a,b)
          return a > b
        end
      end
      -- protected sort
      local psort = function(s,a,b)
        local ok,res = pcall(s,a,b)
        if not ok or not res then
          return false
        else
          return true
        end
      end
      if options.sort.byValue == true or options.sort.byValue == '' then
        if options.sort.descending then
          sort = function(a,b)
            return psort(gt,a.value,b.value)
          end
        else
          sort = function(a,b)
            return psort(lt,a.value,b.value)
          end
        end
      end
    end
    
    local sorter = function(notification,initializing)
      local event = notification.event
      local path = notification.path
      local value = notification.value
      if event == 'remove' then
        matching[path] = nil
      else
        matching[path] = {
          path = path,
          value = value,
        }
      end
      if initializing then
        return
      end
      local new_sorted = {}
      for _,entry in pairs(matching) do
        tinsert(new_sorted,entry)
      end
      tsort(new_sorted,sort)
      -- 'first handle index moved'
      local changes = {}
      for i=from,mmin(to,#sorted) do
        if not new_sorted[i] then
          changes[i] = {
            path = sorted[i].path,
            event = 'remove',
            index = i,
            value = sorted[i].value
          }
        else
          if sorted[i].path == new_sorted[i].path then
            if event == 'change' then
              changes[i] = {
                path = new_sorted[i].path,
                event = 'change',
                index = i,
                value = new_sorted[i].value
              }
            end
          else
            local moved
            for j=from,mmin(to,#new_sorted) do
              -- index changed
              if sorted[i].path == new_sorted[j].path then
                assert(i~=j)
                changes[j] = {
                  path = sorted[i].path,
                  event = 'change',
                  index = j,
                  value = sorted[i].value
                }
                -- mark old index as free
                moved = true
                sorted[i] = nil
                break
              end
            end
            if not moved then
              notify
              {
                path = sorted[i].path,
                value = sorted[i].value,
                event = 'remove',
                index = i
              }
              sorted[i] = nil
            end
          end
        end
      end
      for _,change in pairs(changes) do
        notify(change)
      end
      for i=from,to do
        if not sorted[i] and new_sorted[i] and not changes[i] then
          notify
          {
            path = new_sorted[i].path,
            value = new_sorted[i].value,
            event = 'add',
            index = i
          }
        end
      end
      sorted = new_sorted
    end
    
    local flush = function()
      sorted = {}
      for _,entry in pairs(matching) do
        tinsert(sorted,entry)
      end
      tsort(sorted,sort)
      for i=from,to do
        if not sorted[i] then
          break
        end
        notify
        {
          path = sorted[i].path,
          value = sorted[i].value,
          event = 'add',
          index = i
        }
      end
    end
    return sorter,flush
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
    local queue_notification = function(nparams)
      assert(false,'fetcher misbehaves: must not be called yet')
    end
    local notify = function(nparams)
      queue_notification(nparams)
    end
    local sorter_ok,sorter,flush = pcall(create_sorter,params,notify)
    local initializing = true
    if sorter_ok and sorter then
      notify = function(nparams)
        -- the sorter filters all matches and may
        -- reorder them
        sorter(nparams,initializing)
      end
    end
    local params_ok,fetcher = pcall(create_fetcher,params,notify)
    if not params_ok then
      error(invalid_params{fetchParams = params, reason = fetcher})
    end
    
    client.fetchers[fetch_id] = fetcher
    
    if message.id then
      client:queue
      {
        id = message.id,
        result = {}
      }
    end
    local cq = client.queue
    queue_notification = function(nparams)
      cq(client,{
          method = fetch_id,
          params = nparams
      })
    end
    for path,leave in pairs(leaves) do
      fetcher
      {
        path = path,
        value = leave.value,
        event = 'add'
      }
    end
    initializing = false
    if flush then
      flush()
    end
  end
  
  local unfetch = function(client,message)
    local params = message.params
    local fetch_id = checked(params,'id','string')
    client.fetchers[fetch_id] = nil
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
  
  local config = function(client,message)
    local params = message.params
    if params.peer then
      client = nil
      for client_ in pairs(clients) do
        if client_.name == params.peer then
          client = client_
          break
        end
      end
      if not client then
        error('unknown client')
      end
    end
    if params.name then
      client.name = params.name
    end
    if params.encoding then
      if params.encoding == 'msgpack' then
        local ok,cmsgpack = pcall(require,'cmsgpack')
        if not ok then
          error('encoding not supported')
        end
        -- send any outstanding messages with old encoding
        -- and the response to this config call immediatly
        if message.id then
          client:queue
          {
            id = message.id,
            result = true
          }
        end
        client.flush()
        client.is_binary = true
        client.encode = cmsgpack.pack
        client.decode = cmsgpack.unpack
        return nil,true -- set dont_auto_reply true
      end
    end
    client.debug = params.debug
  end
  
  local sync = function(f)
    local sc = function(client,message)
      local ok,result,dont_auto_reply = pcall(f,client,message)
      if message.id and not dont_auto_reply then
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
    config = sync(config),
    add = sync(add),
    remove = sync(remove),
    call = async(route),
    set = async(route),
    fetch = async(fetch),
    unfetch = async(unfetch),
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
          if client.debug then
            debug(client.name or 'unnamed client','->',jencode(message))
          end
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
        local message
        if num == 1 then
          message = client.messages[1]
        elseif num > 1 then
          message = client.messages
        else
          assert(false,'messages must contain at least one element if not nil')
        end
        if client.debug then
          debug(client.name or 'unnamed client','<-',jencode(message))
        end
        send(client.encode(message))
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
      send = function(msg) jsock:send(msg) end,
    }
    client.encode = cjson.encode
    client.decode = cjson.decode
    
    jsock:on_message(function(_,message)
        dispatch_message(client,client.decode(message))
      end)
    jsock:on_close(function(_,...)
        debug('client socket close ('..(client.name or '')..')',...)
        client:release()
      end)
    jsock:on_error(function(_,...)
        crit('client socket error ('..(client.name or '')..')',...)
        client:release()
      end)
    jsock:read_io():start(loop)
    clients[client] = client
  end
  
  local accept_websocket = function(ws)
    local client
    client = create_client
    {
      close = function()
        ws:close()
      end,
      send = function(msg)
        local type
        if client.is_binary then
          type = 2
        else
          type = 1
        end
        ws:send(msg,type)
      end,
    }
    client.encode = cjson.encode
    client.decode = cjson.decode
    
    ws:on_message(function(_,msg,opcode)
        dispatch_message(client,client.decode(msg))
      end)
    ws:on_close(function(_,...)
        debug('client websocket close ('..(client.name or '')..')',...)
        client:release()
      end)
    ws:on_error(function(_,...)
        crit('client websocket error ('..(client.name or '')..')',...)
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


