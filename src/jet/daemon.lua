local cjson = require'cjson'
local ev = require'ev'
local socket = require'socket'
local jsocket = require'jet.socket'
local jpath_matcher = require'jet.daemon.path_matcher'
local jvalue_matcher = require'jet.daemon.value_matcher'
local jsorter = require'jet.daemon.sorter'
local jfetcher = require'jet.daemon.fetcher'
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
local invalid_params = jutils.invalid_params
local invalid_request = jutils.invalid_request
local response_timeout = jutils.response_timeout
local internal_error = jutils.internal_error
local parse_error = jutils.parse_error
local method_not_found = jutils.method_not_found
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
  local resumables = {}
  
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
      local ok,err = pcall(fetcher.op,path,lpath,event,value)
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
    local params_ok,fetcher
    local notify = function(nparams)
      fetcher.queue(nparams)
    end
    local sorter_ok,sorter,flush = pcall(jsorter.new,params,notify)
    local initializing = true
    if sorter_ok and sorter then
      notify = function(nparams)
        -- the sorter filters all matches and may
        -- reorder them
        sorter(nparams,initializing)
      end
    end
    params_ok,fetcher = pcall(jfetcher.new,params,notify)
    if not params_ok then
      error(invalid_params({fetchParams = params, reason = fetcher}))
    end
    
    peer.fetchers[fetch_id] = fetcher
    
    if fetcher.is_case_insensitive then
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
    
    fetcher.queue = function(nparams)
      peer:queue({
          method = fetch_id,
          params = nparams,
      })
    end
    
    local fetchop = fetcher.op
    for path,element in pairs(elements) do
      local may_have_interest = fetchop(path,has_case_insensitives and path:lower(),'add',element.value)
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
    if not jutils.is_valid_path(path) then
      error(invalid_params({invalidPath = path}))
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
        local ok,may_have_interest = pcall(fetcher.op,path,lpath,'add',value)
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
    
    if params.debug ~= nil then
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
      peer.debug = params.debug
      return
    end
    
    if params.name then
      peer.name = params.name
      return
    end
    
    -- enables message history and makes this peer
    -- resumable in case of close/error event
    -- returns the unique persist id, which
    -- must be used to resume the peer.
    if params.persist ~= nil then
      peer.message_history = {}
      local persist_id = tostring(peer)
      peer.persist_id = persist_id
      peer.persist_time = tonumber(params.persist) or 120
      resumables[persist_id] = peer
      return persist_id
    end
    
    -- if valid resume parameters are passed in,
    -- returns the last received message number (not id)
    -- and resends all missed messages from history.
    -- the peer must have been configured as persistant before.
    if params.resume then
      local persist_id = checked(params.resume,'id','string')
      local received_count = checked(params.resume,'receivedCount','number')
      local resumer = resumables[persist_id]
      if not resumer then
        error(invalid_params({invalidPersistId=persist_id}))
      end
      resumer.mediated = true
      -- check if the daemon has already noticed, that the resumer died
      if resumer.release_timer then
        resumer.release_timer:stop(loop)
        resumer.release_timer:clear_pending(loop)
        resumer.release_timer = nil
      else
        resumer:close()
      end
      local missed_messages_count = resumer.message_count - received_count
      local history = resumer.message_history
      local start = #history-missed_messages_count + 1
      if start < 0 then
        error(internal_error({historyNotAvailable=missed_messages_count}))
      end
      resumer:transfer_fetchers(peer)
      resumer:transfer_elements(peer)
      peer.receive_count = resumer.receive_count
      if message.id then
        peer:queue({
            id = message.id,
            result = peer.receive_count,
        })
      end
      for i=start,#history do
        peer:queue(history[i])
      end
      peer.message_history = {}
      resumables[persist_id] = peer
      peer.persist_id = persist_id
      peer.persist_time = resumer.persist_time
      peer.flush()
      return nil,true -- set dont_auto_reply true
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
      else
        error(invalid_params({encodingNotSupported=params.encoding}))
      end
    end
    
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
      error = method_not_found(message.method)
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
        error = invalid_request(message)
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
                error = invalid_request(message)
            })
          elseif #message > 0 then
            peer.receive_count = peer.receive_count + #message
            for i,message in ipairs(message) do
              dispatch_single_message(peer,message)
            end
          else
            peer.receive_count = peer.receive_count + 1
            dispatch_single_message(peer,message)
          end
        else
          log('invalid json ('..(peer.name or 'unnamed')..')',msg,message)
          peer:queue({error = parse_error(msg)})
        end
      end)
    if not ok then
      crit('dispatching message',jencode(message),err)
    end
    flush_peers()
  end
  
  local create_peer = function(ops)
    local peer = {}
    peer.receive_count = 0
    local release = function()
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
    peer.transfer_fetchers = function(_,new_peer)
      for fetch_id,fetcher in pairs(peer.fetchers) do
        fetcher.queue = function(nparams)
          new_peer:queue({
              method = fetch_id,
              params = nparams
          })
        end
      end
    end
    peer.transfer_elements = function(_,new_peer)
      for _,element in pairs(elements) do
        element.peer = new_peer
      end
    end
    peer.release = function(_)
      if peer then
        if peer.message_history then
          resumables[peer.persist_id] = peer
          peer.release_timer = ev.Timer.new(function()
              peer.release_timer = nil
              if not peer.mediated then
                resumables[peer.persist_id] = nil
                release()
              end
            end,peer.persist_time or 1)
          peer.release_timer:start(loop)
        else
          release()
        end
      end
    end
    peer.close = function(_)
      peer:flush()
      ops.close()
    end
    peer.messages = {}
    peer.queue = function(_,message)
      tinsert(peer.messages,message)
    end
    local send = ops.send
    peer.message_count = 0
    peer.flush = function(_)
      local messages = peer.messages
      local num = #messages
      peer.message_count = peer.message_count + num
      local history = peer.message_history
      if history then
        for _,message in ipairs(messages) do
          tinsert(history,message)
        end
        local history_num = #history
        -- limit history num to 100
        for i=1,(history_num-100) do
          tremove(history,1)
        end
        assert(#history <= 100)
      end
      if num > 0 and not peer.release_timer then
        if num == 1 then
          messages = messages[1]
        end
        if peer.debug then
          debug(peer.name or 'unnamed peer','<-',jencode(messages))
        end
        send(peer.encode(messages))
      end
      peer.messages = {}
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


