local cjson = require'cjson'
local ev = require'ev'
local socket = require'socket'
local jsocket = require'jet.socket'
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local new_timer = ev.Timer.new
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
local mmax = math.max

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

local sbind = function(host,port)
  if socket.tcp6 then
    local server = socket.tcp6()
    local _,err = server:setoption('ipv6-v6only',false)
    if err then
      server:close()
      return nil,err
    end
    _,err = server:setoption("reuseaddr",true)
    if err then
      server:close()
      return nil,err
    end
    _,err = server:bind(host,port)
    if err then
      server:close()
      return nil,err
    end
    _,err = server:listen()
    if err then
      server:close()
      return nil,err
    end
    return server
  else
    return socket.bind(host,port)
  end
end

local invalid_params = function(data)
  local err = {
    code = -32602,
    message = 'Invalid params',
    data = data
  }
  return err
end

local response_timeout = function(data)
  local err = {
    code = -32001,
    message = 'Response Timeout',
    data = data
  }
  return err
end

local create_daemon = function(options)
  
  local options = options or {}
  local port = options.port or 11122
  local loop = options.loop or ev.Loop.default
  
  print = options.print or print
  
  local peers = {}
  local elements = {}
  local routes = {}
  
  local has_case_insensitives
  local case_insensitives = {}
  
  local route_message = function(peer,message)
    local route = routes[message.id]
    if route then
      route.timer:stop(loop)
      routes[message.id] = nil
      message.id = route.id
      route.receiver:queue(message)
    else
      log('unknown route id:',jencode(message))
    end
  end
  
  local publish = function(notification)
    notification.lpath = has_case_insensitives and notification.path:lower()
    for peer in pairs(peers) do
      for fetch_id,fetcher in pairs(peer.fetchers) do
        local ok,refetch = pcall(fetcher,notification)
        if not ok then
          crit('publish failed',fetch_id,refetch)
        elseif refetch then
          for path,element in pairs(elements) do
            fetcher
            {
              path = path,
              value = element.value,
              event = 'add'
            }
          end
        end
      end
    end
  end
  
  local flush_peers = function()
    for peer in pairs(peers) do
      peer:flush()
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
    return function(path,lpath)
      if ci then
        path = lpath
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
            local need_table = where.prop and where.prop ~= '' and where.prop ~= jnull
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
        if not where.prop or where.prop == '' or where.prop == jnull then
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
      local lpath = notification.lpath
      local path = notification.path
      local value = notification.value
      local match,backrefs = path_matcher(path,lpath)
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
              if elements[dep_path] then
                context.deps_ok[dep_path] = deps[dep_path].value_matcher(elements[dep_path].value)
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
    return fetchop,options.caseInsensitive
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
      local lpath = notification.lpath
      local path_matching = true
      if path_matcher and not path_matcher(path,lpath) then
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
    
    return fetchop,options.caseInsensitive
  end
  
  local create_sorter = function(options,notify)
    if not options.sort then
      return nil
    end
    
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
    
    local from = options.sort.from or 1
    local to = options.sort.to or 10
    local sorted = {}
    local matches = {}
    local index = {}
    local n
    
    local is_in_range = function(i)
      return i and i >= from and i <= to
    end
    
    local sorter = function(notification,initializing)
      local event = notification.event
      local path = notification.path
      local value = notification.value
      if initializing then
        if index[path] then
          return
        end
        tinsert(matches,{
            path = path,
            value = value,
        })
        index[path] = #matches
        return
      end
      local last_matches_len = #matches
      local lastindex = index[path]
      if event == 'remove' then
        if lastindex then
          tremove(matches,lastindex)
          index[path] = nil
        else
          return
        end
      elseif lastindex then
        matches[lastindex].value = value
      else
        tinsert(matches,{
            path = path,
            value = value,
        })
      end
      
      tsort(matches,sort)
      
      for i,m in ipairs(matches) do
        index[m.path] = i
      end
      
      if last_matches_len < from and #matches < from then
        return
      end
      
      local newindex = index[path]
      
      -- this may happen due to a refetch :(
      if newindex and lastindex and newindex == lastindex then
        if event == 'change' then
          notify{
            n = n,
            changes = {
              {
                path = path,
                value = value,
                index = newindex,
              }
            }
          }
        end
        return
      end
      
      local start
      local stop
      local is_in = is_in_range(newindex)
      local was_in = is_in_range(lastindex)
      
      if is_in and was_in then
        start = mmin(lastindex,newindex)
        stop = mmax(lastindex,newindex)
      elseif is_in and not was_in then
        start = newindex
        stop = mmin(to,#matches)
      elseif not is_in and was_in then
        start = lastindex
        stop = mmin(to,#matches)
      else
        start = from
        stop = mmin(to,#matches)
      end
      
      local changes = {}
      for i=start,stop do
        local new = matches[i]
        local old = sorted[i]
        if new and new ~= old then
          tinsert(changes,{
              path = new.path,
              value = new.value,
              index = i
          })
        end
        sorted[i] = new
        if not new then
          break
        end
      end
      
      local new_n = mmin(to,#matches) - from + 1
      
      if new_n ~= n or #changes > 0 then
        n = new_n
        notify({
            changes = changes,
            n = n
        })
      end
    end
    
    local flush = function()
      tsort(matches,sort)
      
      for i,m in ipairs(matches) do
        index[m.path] = i
      end
      
      n = 0
      
      local changes = {}
      for i=from,to do
        local new = matches[i]
        if new then
          new.index = i
          n = i - from + 1
          sorted[i] = new
          tinsert(changes,new)
        end
      end
      
      notify({
          changes = changes,
          n = n,
      })
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
          error(invalid_params{wrongType=key,got=params})
        end
      else
        return p
      end
    else
      error(invalid_params{missingParam=key,got=params})
    end
  end
  
  local optional = function(params,key,typename)
    local p = params[key]
    if p ~= nil then
      if typename then
        if type(p) == typename then
          return p
        else
          error(invalid_params{wrongType=key,got=params})
        end
      else
        return p
      end
    end
  end
  
  local change = function(peer,message)
    local notification = message.params
    local path = checked(notification,'path','string')
    local element = elements[path]
    if element then
      element.value = notification.value
      notification.event = 'change'
      publish(notification)
    else
      local error = invalid_params{invalid_path=path}
      if message.id then
        peer:queue
        {
          id = message.id,
          error = error
        }
      else
        log('post failed',jencode(message))
      end
    end
  end
  
  local fetch = function(peer,message)
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
    local params_ok,fetcher,is_case_insensitive = pcall(create_fetcher,params,notify)
    if not params_ok then
      error(invalid_params{fetchParams = params, reason = fetcher})
    end
    
    peer.fetchers[fetch_id] = fetcher
    
    if is_case_insensitive then
      case_insensitives[fetcher] = true
      has_case_insensitives = true
    end
    
    if not flush then
      if message.id then
        peer:queue
        {
          id = message.id,
          result = {}
        }
      end
    end
    
    local cq = peer.queue
    queue_notification = function(nparams)
      cq(peer,{
          method = fetch_id,
          params = nparams
      })
    end
    for path,element in pairs(elements) do
      fetcher
      {
        path = path,
        lpath = has_case_insensitives and path:lower(),
        value = element.value,
        event = 'add'
      }
    end
    initializing = false
    if flush then
      if message.id then
        peer:queue
        {
          id = message.id,
          result = {}
        }
      end
      flush()
    end
  end
  
  local unfetch = function(peer,message)
    local params = message.params
    local fetch_id = checked(params,'id','string')
    local fetcher = peer.fetchers[fetch_id]
    peer.fetchers[fetch_id] = nil
    
    case_insensitives[fetcher] = nil
    has_case_insensitives = pairs(case_insensitives)(case_insensitives) ~= nil
    
    if message.id then
      peer:queue
      {
        id = message.id,
        result = {}
      }
    end
  end
  
  local route = function(peer,message)
    local params = message.params
    local path = checked(params,'path','string')
    local timeout = optional(params,'timeout','number') or 5
    local element = elements[path]
    if element then
      local id
      local mid = message.id
      if mid then
        local timer = new_timer(function()
            routes[id] = nil
            peer:queue
            {
              id = mid,
              error = response_timeout(params)
            }
            peer:flush()
          end,timeout)
        timer:start(loop)
        id = mid..tostring(peer)
        assert(not routes[id])
        -- save route to forward reply
        routes[id] = {
          receiver = peer,
          id = mid,
          timer = timer
        }
      end
      local req = {
        id = id,-- maybe nil
        method = path
      }
      
      local value = params.value
      if value ~= nil then
        req.params = {value = value}
      else
        req.params = params.args or {}
      end
      element.peer:queue(req)
    else
      local error = invalid_params{notExists=path}
      if message.id then
        peer:queue
        {
          id = message.id,
          error = error
        }
      end
      log('route failed',jencode(error))
    end
  end
  
  local add = function(peer,message)
    local params = message.params
    local path = checked(params,'path','string')
    if elements[path] then
      error(invalid_params{exists = path})
    end
    local value = params.value-- might be nil for actions / methods
    local element = {
      peer = peer,
      value = value
    }
    elements[path] = element
    publish
    {
      path = path,
      event = 'add',
      value = value
    }
  end
  
  local remove = function(peer,message)
    local params = message.params
    local path = checked(params,'path','string')
    if not elements[path] then
      error(invalid_params{invalid_path = path})
    end
    local element = assert(elements[path])
    elements[path] = nil
    publish
    {
      path = path,
      event = 'remove',
      value = element.value
    }
  end
  
  local config = function(peer,message)
    local params = message.params
    if params.peer then
      peer = nil
      for peer_ in pairs(peers) do
        if peer_.name == params.peer then
          peer = peer_
          break
        end
      end
      if not peer then
        error('unknown peer')
      end
    end
    if params.name then
      peer.name = params.name
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
          peer:queue
          {
            id = message.id,
            result = true
          }
        end
        peer.flush()
        peer.is_binary = true
        peer.encode = cmsgpack.pack
        peer.decode = cmsgpack.unpack
        return nil,true -- set dont_auto_reply true
      end
    end
    peer.debug = params.debug
  end
  
  local sync = function(f)
    local sc = function(peer,message)
      local ok,result,dont_auto_reply = pcall(f,peer,message)
      if message.id and not dont_auto_reply then
        if ok then
          peer:queue
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
          peer:queue
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
    local ac = function(peer,message)
      local ok,err = pcall(f,peer,message)
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
          peer:queue
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
    echo = sync(function(peer,message)
        return message.params
      end)
  }
  
  local dispatch_request = function(peer,message)
    local error
    assert(message.method)
    local service = services[message.method]
    if service then
      local ok,err = pcall(service,peer,message)
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
    peer:queue
    {
      id = message.id,
      error = error
    }
  end
  
  local dispatch_notification = function(peer,message)
    local service = services[message.method]
    if service then
      local ok,err = pcall(service,peer,message)
      if not ok then
        log('dispatch_notification error:',jencode(err))
      end
    end
  end
  
  local dispatch_single_message = function(peer,message)
    if message.id then
      if message.method then
        dispatch_request(peer,message)
      elseif message.result or message.error then
        route_message(peer,message)
      else
        peer:queue
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
      dispatch_notification(peer,message)
    else
      log('message not dispatched:',jencode(message))
    end
  end
  
  local dispatch_message = function(peer,message,err)
    local ok,err = pcall(
      function()
        if message then
          if peer.debug then
            debug(peer.name or 'unnamed peer','->',jencode(message))
          end
          if message == jnull then
            peer:queue
            {
              error = {
                code = -32600,
                message = 'Invalid Request',
                data = 'message is null'
              }
            }
          elseif #message > 0 then
            for i,message in ipairs(message) do
              dispatch_single_message(peer,message)
            end
          else
            dispatch_single_message(peer,message)
          end
        else
          peer:queue
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
    flush_peers()
  end
  
  local create_peer = function(ops)
    local peer = {}
    peer.release = function()
      if peer then
        for _,fetcher in pairs(peer.fetchers) do
          case_insensitives[fetcher] = nil
        end
        has_case_insensitives = pairs(case_insensitives)(case_insensitives) ~= nil
        peer.fetchers =  {}
        for path,element in pairs(elements) do
          if element.peer == peer then
            publish
            {
              event = 'remove',
              path = path,
              value = element.value
            }
            elements[path] = nil
          end
        end
        flush_peers()
        ops.close()
        peers[peer] = nil
        peer = nil
      end
    end
    peer.close = function(_)
      peer:flush()
      ops.close()
    end
    peer.queue = function(_,message)
      if not peer.messages then
        peer.messages = {}
      end
      tinsert(peer.messages,message)
    end
    local send = ops.send
    peer.flush = function(_)
      if peer.messages then
        local num = #peer.messages
        local message
        if num == 1 then
          message = peer.messages[1]
        elseif num > 1 then
          message = peer.messages
        else
          assert(false,'messages must contain at least one element if not nil')
        end
        if peer.debug then
          debug(peer.name or 'unnamed peer','<-',jencode(message))
        end
        send(peer.encode(message))
        peer.messages = nil
      end
    end
    peer.fetchers = {}
    return peer
  end
  
  local listener
  local accept_tcp = function(loop,accept_io)
    local sock = listener:accept()
    if not sock then
      log('accepting peer failed')
      return
    end
    local jsock = jsocket.wrap(sock)
    local peer = create_peer
    {
      close = function() jsock:close() end,
      send = function(msg) jsock:send(msg) end,
    }
    peer.encode = cjson.encode
    peer.decode = cjson.decode
    
    jsock:on_message(function(_,message)
        dispatch_message(peer,peer.decode(message))
      end)
    jsock:on_close(function(_,...)
        debug('peer socket close ('..(peer.name or '')..')',...)
        peer:release()
      end)
    jsock:on_error(function(_,...)
        crit('peer socket error ('..(peer.name or '')..')',...)
        peer:release()
      end)
    jsock:read_io():start(loop)
    peers[peer] = peer
  end
  
  local accept_websocket = function(ws)
    local peer
    peer = create_peer
    {
      close = function()
        ws:close()
      end,
      send = function(msg)
        local type
        if peer.is_binary then
          type = 2
        else
          type = 1
        end
        ws:send(msg,type)
      end,
    }
    peer.encode = cjson.encode
    peer.decode = cjson.decode
    
    ws:on_message(function(_,msg,opcode)
        dispatch_message(peer,peer.decode(msg))
      end)
    ws:on_close(function(_,...)
        debug('peer websocket close ('..(peer.name or '')..')',...)
        peer:release()
      end)
    ws:on_error(function(_,...)
        crit('peer websocket error ('..(peer.name or '')..')',...)
        peer:release()
      end)
    peers[peer] = peer
  end
  
  local listen_io
  local websocket_server
  
  local daemon = {
    start = function()
      listener = assert(sbind('*',port))
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
      for _,peer in pairs(peers) do
        peer:close()
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


