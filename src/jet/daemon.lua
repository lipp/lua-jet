local cjson = require'cjson'
local ev = require'ev'
local socket = require'socket'
local jsocket = require'jet.socket'

local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local new_timer = ev.Timer.new
local tsort = table.sort
local jencode = cjson.encode
local jdecode = cjson.decode
local jnull = cjson.null
local unpack = unpack
local mmin = math.min
local mmax = math.max
local smatch = string.match

local noop = function() end

--- creates and returns an error table conforming to
-- JSON-RPC Invalid params.
local invalid_params = function(data)
  local err = {
    code = -32602,
    message = 'Invalid params',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Response Timeout.
local response_timeout = function(data)
  local err = {
    code = -32001,
    message = 'Response Timeout',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Internal Error.
local internal_error = function(data)
  local err = {
    code = -32003,
    message = 'Internal error',
    data = data,
  }
  return err
end

local is_empty_table = function(t)
  return pairs(t)(t) == nil
end

--- creates and returns a new daemon instance.
-- options is a table which allows daemon configuration.
local create_daemon = function(options)
  local options = options or {}
  local port = options.port or 11122
  local loop = options.loop or ev.Loop.default
  local log = options.log or noop
  local info = options.info or noop
  local crit = options.crit or noop
  local debug = options.debug or noop
  
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
            fetcher({
                path = path,
                value = element.value,
                event = 'add',
            })
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
  
  local lower_path_smatch = function(path,lpath)
    return smatch(lpath)
  end
  
  local is_exact = function(matcher)
    return matcher:match('^%^([^*]+)%$$')
  end
  
  local is_partial = function(matcher)
    return matcher:match('^%^?%*?([^*]+)%*?%$?$')
  end
  
  local sfind = string.find
  
  local sfind_plain = function(a,b)
    return sfind(a,b,1,true)
  end
  
  local create_path_matcher = function(options)
    if not options.match and not options.unmatch and not options.equalsNot then
      return nil
    end
    local ci = options.caseInsensitive
    local unmatch = {}
    local match = {}
    local equals_not = {}
    local equals = {}
    for i,matcher in ipairs(options.match or {}) do
      local exact = is_exact(matcher)
      local partial = is_partial(matcher)
      if exact then
        if ci then
          equals[exact:lower()] = true
        else
          equals[exact] = true
        end
      elseif partial then
        if ci then
          match[partial:lower()] = sfind_plain
        else
          match[partial] = sfind_plain
        end
      else
        if ci then
          match[matcher:lower()] = smatch
        else
          match[matcher] = smatch
        end
      end
    end
    
    for i,unmatcher in ipairs(options.unmatch or {}) do
      local exact = is_exact(unmatcher)
      local partial = is_partial(unmatcher)
      if exact then
        if ci then
          equals_not[exact:lower()] = true
        else
          equals_not[exact] = true
        end
      elseif partial then
        if ci then
          unmatch[partial:lower()] = sfind_plain
        else
          unmatch[partial] = sfind_plain
        end
      else
        if ci then
          unmatch[unmatcher:lower()] = smatch
        else
          unmatch[unmatcher] = smatch
        end
      end
    end
    
    for i,eqnot in ipairs(options.equalsNot or {}) do
      if ci then
        equals_not[eqnot:lower()] = true
      else
        equals_not[eqnot] = true
      end
    end
    
    if is_empty_table(equals_not) then
      equals_not = nil
    end
    
    if is_empty_table(equals) then
      equals = nil
    end
    
    if is_empty_table(match) then
      match = nil
    end
    
    if is_empty_table(unmatch) then
      unmatch = nil
    end
    
    local pairs = pairs
    
    return function(path,lpath)
      if ci then
        path = lpath
      end
      if equals then
        for eq in pairs(equals) do
          if path == eq then
            return true
          end
        end
      end
      if unmatch then
        for unmatch,f in pairs(unmatch) do
          if f(path,unmatch) then
            return false
          end
        end
      end
      if equals_not then
        for eqnot in pairs(equals_not) do
          if eqnot == path then
            return false
          end
        end
      end
      if match then
        for match,f in pairs(match) do
          if f(path,match) then
            return true
          end
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
  
  local create_fetcher = function(options,notify)
    local path_matcher = create_path_matcher(options)
    local value_matcher = create_value_matcher(options)
    local added = {}
    
    local fetchop = function(notification)
      local path = notification.path
      local lpath = notification.lpath
      if path_matcher and not path_matcher(path,lpath) then
        return false
      end
      local is_matching = true
      local value = notification.value
      if value_matcher and not value_matcher(value) then
        is_matching = false
      end
      local is_added = added[path]
      if not is_matching or notification.event == 'remove' then
        if is_added then
          added[path] = nil
          notify({
              path = path,
              event = 'remove',
              value = value,
          })
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
      notify({
          path = path,
          event = event,
          value = value,
      })
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
          notify({
              n = n,
              changes = {
                {
                  path = path,
                  value = value,
                  index = newindex,
                }
              }
          })
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
              index = i,
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
            n = n,
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
  
  local checked = function(params,key,typename)
    local p = params[key]
    if p ~= nil then
      if typename then
        if type(p) == typename then
          return p
        else
          error(invalid_params({wrongType=key,got=params}))
        end
      else
        return p
      end
    else
      error(invalid_params({missingParam=key,got=params}))
    end
  end
  
  local optional = function(params,key,typename)
    local p = params[key]
    if p ~= nil then
      if typename then
        if type(p) == typename then
          return p
        else
          error(invalid_params({wrongType=key,got=params}))
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
    if element and element.peer == peer then
      element.value = notification.value
      notification.event = 'change'
      publish(notification)
      return
    elseif not element then
      error(invalid_params({pathNotExists=path}))
    else
      assert(element.peer ~= peer)
      error(invalid_params({foreignPath=path}))
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
      error(invalid_params({fetchParams = params, reason = fetcher}))
    end
    
    peer.fetchers[fetch_id] = fetcher
    
    if is_case_insensitive then
      case_insensitives[fetcher] = true
      has_case_insensitives = true
    end
    
    if not flush then
      if message.id then
        peer:queue({
            id = message.id,
            result = true,
        })
      end
    end
    
    local cq = peer.queue
    queue_notification = function(nparams)
      cq(peer,{
          method = fetch_id,
          params = nparams,
      })
    end
    for path,element in pairs(elements) do
      fetcher({
          path = path,
          lpath = has_case_insensitives and path:lower(),
          value = element.value,
          event = 'add',
      })
    end
    initializing = false
    if flush then
      if message.id then
        peer:queue({
            id = message.id,
            result = true,
        })
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
    has_case_insensitives = not is_empty_table(case_insensitives)
    
    if message.id then
      peer:queue({
          id = message.id,
          result = true,
      })
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
            peer:queue({
                id = mid,
                error = response_timeout(params),
            })
            peer:flush()
          end,timeout)
        timer:start(loop)
        id = mid..tostring(peer)
        assert(not routes[id])
        -- save route to forward reply
        routes[id] = {
          receiver = peer,
          id = mid,
          timer = timer,
        }
      end
      local req = {
        id = id,-- maybe nil
        method = path,
      }
      
      local value = params.value
      if value ~= nil then
        req.params = {value = value}
      else
        req.params = params.args or {}
      end
      element.peer:queue(req)
    else
      local error = invalid_params({pathNotExists=path})
      if message.id then
        peer:queue({
            id = message.id,
            error = error,
        })
      end
      log('route failed',jencode(error))
    end
  end
  
  local add = function(peer,message)
    local params = message.params
    local path = checked(params,'path','string')
    local element = elements[path]
    if element then
      error(invalid_params({pathAlreadyExists = path}))
    end
    local value = params.value-- might be nil for actions / methods
    element = {
      peer = peer,
      value = value,
    }
    elements[path] = element
    publish({
        path = path,
        event = 'add',
        value = value,
    })
  end
  
  local remove = function(peer,message)
    local params = message.params
    local path = checked(params,'path','string')
    local element = elements[path]
    if element and element.peer == peer then
      elements[path] = nil
      publish({
          path = path,
          event = 'remove',
          value = element.value,
      })
      return
    elseif not element then
      error(invalid_params({pathNotExists=path}))
    else
      assert(element.peer ~= peer)
      error(invalid_params({foreignPath=path}))
    end
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
          error(invalid_params({encodingNotSupported='msgpack'}))
        end
        -- send any outstanding messages with old encoding
        -- and the response to this config call immediatly
        if message.id then
          peer:queue({
              id = message.id,
              result = true,
          })
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
          if type(result) == 'nil' then
            result = true
          end
          peer:queue({
              id = message.id,
              result = result,
          })
        else
          local error
          if type(result) == 'table' and result.code and result.message then
            error = result
          else
            error = internal_error(result)
          end
          peer:queue({
              id = message.id,
              error = error,
          })
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
            error = internal_error(err)
          end
          peer:queue({
              id = message.id,
              error = err,
          })
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
    local service = services[message.method]
    if service then
      local ok,err = pcall(service,peer,message)
      if ok then
        return
      else
        if type(err) == 'table' and err.code and err.message then
          error = err
        else
          error = internal_error(err)
        end
      end
    else
      error = {
        code = -32601,
        message = 'Method not found',
        data = message.method,
      }
    end
    peer:queue({
        id = message.id,
        error = error,
    })
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
        return
      elseif message.result or message.error then
        route_message(peer,message)
        return
      end
    elseif message.method then
      dispatch_notification(peer,message)
      return
    end
    log('invalid request:',jencode(message))
    peer:queue({
        id = message.id,
        error = {
          code = -32600,
          message = 'Invalid Request',
          data = message,
        }
    })
  end
  
  local dispatch_message = function(peer,msg)
    local ok,err = pcall(
      function()
        local ok,message = pcall(peer.decode,msg)
        if ok then
          if peer.debug then
            debug(peer.name or 'unnamed peer','->',jencode(message))
          end
          if type(message) ~= 'table' then
            peer:queue({
                error = {
                  code = -32600,
                  message = 'Invalid Request',
                  data = message,
                }
            })
          elseif #message > 0 then
            for i,message in ipairs(message) do
              dispatch_single_message(peer,message)
            end
          else
            dispatch_single_message(peer,message)
          end
        else
          log('invalid json ('..(peer.name or 'unnamed')..')',msg,message)
          peer:queue({
              error = {
                code  = -32700,
                message = 'Parse error',
                data = msg,
              }
          })
        end
      end)
    if not ok then
      crit('dispatching message',jencode(message),err)
    end
    flush_peers()
  end
  
  local create_peer = function(ops)
    local peer = {}
    peer.release = function(_)
      if peer then
        for _,fetcher in pairs(peer.fetchers) do
          case_insensitives[fetcher] = nil
        end
        has_case_insensitives = not is_empty_table(case_insensitives)
        peer.fetchers = {}
        peers[peer] = nil
        for path,element in pairs(elements) do
          if element.peer == peer then
            publish({
                event = 'remove',
                path = path,
                value = element.value,
            })
            elements[path] = nil
          end
        end
        flush_peers()
        ops.close()
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
    peer.encode = cjson.encode
    peer.decode = cjson.decode
    
    return peer
  end
  
  local accept_tcp = function(jsock)
    local peer = create_peer({
        close = function() jsock:close() end,
        send = function(msg) jsock:send(msg) end,
    })
    
    jsock:on_message(function(_,message_string)
        dispatch_message(peer,message_string)
      end)
    jsock:on_close(function(_,...)
        debug('peer socket close ('..(peer.name or '')..')',...)
        peer:release()
      end)
    jsock:on_error(function(_,...)
        crit('peer socket error ('..(peer.name or '')..')',...)
        peer:release()
      end)
    peers[peer] = peer
  end
  
  local accept_websocket = function(ws)
    local peer
    peer = create_peer({
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
    })
    
    ws:on_message(function(_,message_string)
        dispatch_message(peer,message_string)
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
  
  local websocket_server
  local server
  
  local daemon = {
    start = function()
      server = jsocket.listener({
          port = port,
          log = log,
          loop = loop,
          on_connect = accept_tcp
      })
      
      if options.ws_port then
        local websocket_ok,err = pcall(function()
            websocket_server = require'websocket'.server.ev.listen({
                port = options.ws_port,
                protocols = {
                  jet = accept_websocket
                }
            })
          end)
        if not websocket_ok then
          crit('Could not start websocket server',err)
        end
      end
    end,
    stop = function()
      server:close()
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
  new = create_daemon,
}


