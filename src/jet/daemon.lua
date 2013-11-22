local cjson = require'cjson'
local ev = require'ev'
local socket = require'socket'
local jsocket = require'jet.socket'
local jpath_matcher = require'jet.daemon.path_matcher'
local jvalue_matcher = require'jet.daemon.value_matcher'
local jutils = require'jet.utils'

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

local noop = jutils.noop

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

local is_empty_table = jutils.is_empty_table

--- creates and returns a new daemon instance.
-- options is a table which allows daemon configuration.
local create_daemon = function(options)
  local options = options or {}
  local port = options.port or 11122
  local loop = options.loop or ev.Loop.default
  
  -- logging functions
  local log = options.log or noop
  local info = options.info or noop
  local crit = options.crit or noop
  local debug = options.debug or noop
  
  -- all connected peers (clients)
  -- key and value are peer itself (table)
  local peers = {}
  
  -- all elements which have been added
  -- key is (unique) path, value is element (table)
  local elements = {}
  
  -- holds info about all pending request
  -- key is (daemon generated) unique id, value is table
  -- with original id and receiver (peer) and request
  -- timeout timer.
  local routes = {}
  
  -- global for tracking the neccassity of lower casing
  -- paths on publish
  local has_case_insensitives
  -- holds all case insensitive fetchers
  -- key is fetcher (table), value is true
  local case_insensitives = {}
  
  -- routes an incoming response to the requestor (peer)
  -- stops the request timeout eventually
  local route_response = function(peer,message)
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
  
  -- make often refered globals local to speed up lookup
  local pcall = pcall
  local pairs = pairs
  
  -- publishes a notification
  local publish = function(path,event,value,element)
    local lpath = has_case_insensitives and path:lower()
    for fetcher in pairs(element.fetchers) do
      local ok,err = pcall(fetcher,path,lpath,event,value)
      if not ok then
        crit('publish failed',err,path,event)
      end
    end
  end
  
  -- flush all outstanding / queued messages to the peer socket
  local flush_peers = function()
    for peer in pairs(peers) do
      peer:flush()
    end
  end
  
  -- creates a fetcher function, eventually combining path and/or value
  -- matchers.
  -- additionally returns, if the resulting fetcher is case insensitive and thus
  -- requires paths to be available as lowercase.
  local create_fetcher = function(options,notify)
    local path_matcher = jpath_matcher.new(options)
    local value_matcher = jvalue_matcher.new(options)
    
    local fetchop
    
    if path_matcher and not value_matcher then
      fetchop = function(path,lpath,event,value,element)
        if not path_matcher(path,lpath) then
          -- return false to indicate NO further interest
          return false
        end
        notify({
            path = path,
            event = event,
            value = value,
        })
        -- return true to indicate further interest
        return true
      end
      
    elseif not path_matcher and value_matcher then
      local added = {}
      fetchop = function(path,lpath,event,value,element)
        local is_added = added[path]
        if event == 'remove' or not value_matcher(value) then
          if is_added then
            added[path] = nil
            notify({
                path = path,
                event = 'remove',
                value = value,
            })
          end
          -- return false to indicate NO further interest
          return false
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
        -- return true to indicate further interest
        return true
      end
    elseif path_matcher and value_matcher then
      local added = {}
      fetchop = function(path,lpath,event,value,element)
        if not path_matcher(path,lpath) then
          -- return false to indicate NO further interest
          return false
        end
        local is_added = added[path]
        if event == 'remove' or not value_matcher(value) then
          if is_added then
            added[path] = nil
            notify({
                path = path,
                event = 'remove',
                value = value,
            })
          end
          -- return true to indicate further interest
          return true
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
        -- return true to indicate further interest
        return true
      end
    else
      fetchop = function(path,lpath,event,value)
        notify({
            path = path,
            event = event,
            value = value,
        })
        -- return true to indicate further interest
        return true
      end
      options.caseInsensitive = false
    end
    
    return fetchop,options.caseInsensitive
  end
  
  -- may create and return a sorter function.
  -- the sort function is based on the options.sort entries.
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
  
  -- checks if the "params" table has the key "key" with type "typename".
  -- if so, returns the value, else throws invalid params error.
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
  
  -- checks if the "params" table has the key "key" with type "typename".
  -- if tyoe mismatches throws invalid params error, else returns the
  -- value or nil if not present.
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
  
  -- dispatches the "change" jet call.
  -- updates the internal cache (elements table)
  -- and publishes a change event.
  local change = function(peer,message)
    local notification = message.params
    local path = checked(notification,'path','string')
    local element = elements[path]
    if element and element.peer == peer then
      element.value = notification.value
      publish(path,'change',element.value,element)
      return
    elseif not element then
      error(invalid_params({pathNotExists=path}))
    else
      assert(element.peer ~= peer)
      error(invalid_params({foreignPath=path}))
    end
  end
  
  -- dispatches the "fetch" jet call.
  -- creates a fetch operation and optionally a sorter.
  -- all elements are inputed as "fake" add events. The fetchop
  -- is associated with the element if the fetchop "shows interest"
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
      local may_have_interest = fetcher(path,has_case_insensitives and path:lower(),'add',element.value)
      if may_have_interest then
        element.fetchers[fetcher] = true
      end
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
  
  -- dispatches the "unfetch" jet call.
  -- removes all ressources associsted wth the fetcher.
  local unfetch = function(peer,message)
    local params = message.params
    local fetch_id = checked(params,'id','string')
    local fetcher = peer.fetchers[fetch_id]
    peer.fetchers[fetch_id] = nil
    
    case_insensitives[fetcher] = nil
    has_case_insensitives = not is_empty_table(case_insensitives)
    
    for _,element in pairs(elements) do
      element.fetchers[fetcher] = nil
    end
    
    if message.id then
      peer:queue({
          id = message.id,
          result = true,
      })
    end
  end
  
  -- routes / forwards a request ("call","set") to the corresponding peer.
  -- creates an entry in the "route" table and sets up a timer
  -- which will respond a response timeout error to the requestor if
  -- no corresponding response is received.
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
      fetchers = {},
    }
    elements[path] = element
    
    local lpath = has_case_insensitives and path:lower()
    
    -- filter out fetchers, which will never ever
    -- match / have interest in this element (fetchers, which
    -- don't depend on the value of the element).
    for peer in pairs(peers) do
      for _,fetcher in pairs(peer.fetchers) do
        local ok,may_have_interest = pcall(fetcher,path,lpath,'add',value)
        if ok then
          if may_have_interest then
            element.fetchers[fetcher] = true
          end
        else
          crit('publish failed',may_have_interest,path,'add')
        end
      end
    end
  end
  
  local remove = function(peer,message)
    local params = message.params
    local path = checked(params,'path','string')
    local element = elements[path]
    if element and element.peer == peer then
      elements[path] = nil
      publish(path,'remove',element.value,element)
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
        route_response(peer,message)
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
          for _,element in pairs(elements) do
            element.fetchers[fetcher] = nil
          end
        end
        has_case_insensitives = not is_empty_table(case_insensitives)
        peer.fetchers = {}
        peers[peer] = nil
        for path,element in pairs(elements) do
          if element.peer == peer then
            publish(path,'remove',element.value,element)
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


