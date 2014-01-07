local jsocket = require'jet.socket'
local socket = require'socket'
local ev = require'ev'
local cjson = require'cjson'
local jutils = require'jet.utils'
local step = require'step'

local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat

local noop = jutils.noop
local invalid_params = jutils.invalid_params
local internal_error = jutils.internal_error
local method_not_found = jutils.method_not_found

local error_object = function(err)
  local error
  if type(err) == 'table' and err.code and err.message then
    error = err
  else
    error = internal_error(err)
  end
  return error
end

local eps = 2^-40

local detach = function(f,loop)
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

local noop = function() end

new = function(config)
  config = config or {}
  local log = config.log or noop
  local ip = config.ip or '127.0.0.1' -- localhost'
  local port = config.port or 11122
  local encode = cjson.encode
  local decode = cjson.decode
  local log = config.log or noop
  if config.sync then
    local sock = socket.connect(ip,port)
    if not sock then
      error('could not connect to jetd with ip:'..ip..' port:'..port)
    end
    local wsock = jsocket.wrap_sync(sock)
    local id = 0
    local service = function(method,params,timeout)
      local rid
      id = id + 1
      rid = id
      params.timeout = timeout -- maybe nil, defaults to 5secs at daemon
      wsock:send(encode
        {
          id = rid,
          method = method,
          params = params
      })
      local response,err = wsock:receive()
      if err then
        error(err)
      end
      response = decode(response)
      assert(response.id == rid)
      if response.result then
        return response.result
      elseif response.error then
        error(response.error,2)
      else
        assert(false,'invalid response:'..cjson.encode(response))
      end
    end
    local j_sync = {}
    j_sync.call = function(_,path,params,timeout)
      return service('call',{path=path,args=params or {}},timeout)
    end
    j_sync.set = function(_,path,value,timeout)
      return service('set',{path=path,value=value},timeout)
    end
    j_sync.config = function(_,params,timeout)
      return service('config',params,timeout)
    end
    j_sync.state = function(_,params,timeout)
      return service('add',params,timeout)
    end
    return j_sync
  else
    local loop = config.loop or ev.Loop.default
    local wsock = jsocket.new({ip = ip, port = port, loop = loop})
    local messages = {}
    local queue = function(message)
      tinsert(messages,message)
    end
    local message_count = 0
    local message_history = {}
    local pending
    local will_flush = true
    local flush
    local is_persistant
    
    if not config.persist then
      flush = function(reason)
        local n = #messages
        if n == 1 then
          wsock:send(encode(messages[1]))
        elseif n > 1 then
          wsock:send(encode(messages))
        end
        messages = {}
        will_flush = false
      end
    else
      flush = function(reason)
        local num = #messages
        if not is_persistant then
          message_count = message_count + num
        end
        local history = message_history
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
        if not pending then
          if num == 1 then
            wsock:send(encode(messages[1]))
          elseif num > 1 then
            wsock:send(encode(messages))
          end
        end
        messages = {}
        will_flush = false
      end
    end
    
    local request_dispatchers = {}
    local response_dispatchers = {}
    local dispatch_response = function(self,message)
      local mid = message.id
      local callbacks = response_dispatchers[mid]
      assert(mid,cjson.encode(message))
      response_dispatchers[mid] = nil
      if callbacks then
        if message.result then
          if callbacks.success then
            callbacks.success(message.result)
          end
        elseif message.error then
          if callbacks.error then
            callbacks.error(message.error)
          end
        else
          log('invalid result:',cjson.encode(message))
        end
      else
        log('invalid result id:',mid,cjson.encode(message))
      end
    end
    local on_no_dispatcher
    -- handles both method calls and fetchers (notifications)
    local dispatch_request = function(self,message)
      local dispatcher = request_dispatchers[message.method]
      local error
      if dispatcher then
        local error
        local ok,err = pcall(dispatcher,self,message)
        if ok then
          return
        else
          error = error_object(err)
        end
      else
        error = method_not_found(message.method)
        if on_no_dispatcher then
          pcall(on_no_dispatcher,message)
        end
      end
      local mid = message.id
      if error and mid then
        queue
        {
          id = mid,
          error = error
        }
      end
    end
    local received_count = 0
    local dispatch_single_message = function(self,message)
      if message.method and message.params then
        dispatch_request(self,message)
      elseif message.result or message.error then
        dispatch_response(self,message)
      else
        log('unhandled message',cjson.encode(message))
      end
    end
    local dispatch_message = function(self,message)
      local ok,message = pcall(decode,message)
      if not ok then
        log('decoding message failed',ok)
        return
      end
      will_flush = true
      if message then
        local num = #message
        if num > 0 then
          -- The received count MUST be incremented here for arrays!
          -- This is relevant for resuming...
          received_count = received_count + num
          for i,message in ipairs(message) do
            dispatch_single_message(self,message)
          end
        else
          received_count = received_count + 1
          dispatch_single_message(self,message)
        end
      else
        queue
        {
          error = {
            code  = -32700,
            messsage = 'Parse error'
          }
        }
      end
      flush('dispatch_message')
    end
    wsock:on_message(dispatch_message)
    wsock:on_error(config.on_error or noop)
    local persist_id
    local closing
    local connect_sequence
    local on_close
    local try = {}
    local j = {}
    on_close = function()
      if not closing and config.persist and not pending then
        messages = {}
        pending = true
        encode = cjson.encode
        decode = cjson.decode
        wsock = jsocket.new({ip = ip, port = port, loop = loop})
        wsock:on_message(dispatch_message)
        wsock:on_error(config.on_error or noop)
        wsock:on_close(on_close)
        wsock:on_connect(function()
            is_persistant = false
            connect_sequence = step.new({
                try = try,
                catch = function(err)
                  j:close()
                end,
                finally = function()
                  if config.on_connect then
                    config.on_connect(j)
                    config.on_connect = nil
                  end
                  flush('on_connect')
                end
            })
            
            connect_sequence()
            flush('resume')
          end)
        
        ev.Timer.new(function(loop,io)
            if pending and not closing then
              wsock:connect()
            else
              io:stop(loop)
            end
          end,0.5,0.5):start(loop)
      end
      
      if config.on_close then
        config.on_close()
      end
    end
    
    wsock:on_close(on_close)
    
    j.loop = function()
      loop:loop()
    end
    
    j.on_no_dispatcher = function(_,f)
      on_no_dispatcher = f
    end
    
    j.on_error = function(_,f)
      wsock:on_error(f)
    end
    
    j.close = function(self,done,debug_resume)
      flush('close')
      wsock:close()
      if debug_resume then
        return
      end
      closing = true
      if done then
        if config.persist then
          -- the daemon keeps states for config.persist seconds.
          -- during this time, the states / paths are still blocked
          -- by this peer. wait some seconds more and asume
          -- all peer related resources are freed by the daemon.
          ev.Timer.new(function()
              done()
            end,config.persist + 2):start(loop)
        else
          detach(done,loop)
        end
      end
    end
    
    local id = 0
    local service = function(method,params,complete,callbacks)
      local rpc_id
      -- Only make a Request, if callbacks are specified.
      -- Make complete call in case of success.
      -- If no id is specified in the message, no Response
      -- is expected, aka Notification.
      if callbacks then
        params.timeout = callbacks.timeout
        id = id + 1
        rpc_id = id
        if complete then
          if callbacks.success then
            local success = callbacks.success
            callbacks.success = function(result)
              complete(true)
              success()
            end
          else
            callbacks.success = function()
              complete(true)
            end
          end
          
          if callbacks.error then
            local error = callbacks.error
            callbacks.error = function(result)
              complete(false)
              error()
            end
          else
            callbacks.error = function()
              complete(false)
            end
          end
        end
        response_dispatchers[id] = callbacks
      else
        -- There will be no response, so call complete either way
        -- and hope everything is ok
        if complete then
          complete(true)
        end
      end
      local message = {
        id = rpc_id,
        method = method,
        params = params
      }
      if will_flush then
        queue(message)
      else
        wsock:send(encode(message))
      end
    end
    
    j.batch = function(self,action)
      will_flush = true
      action()
      flush('batch')
    end
    
    j.add = function(self,desc,dispatch,callbacks)
      local path = desc.path
      assert(not request_dispatchers[path],path)
      assert(type(path) == 'string',path)
      assert(type(dispatch) == 'function',dispatch)
      local assign_dispatcher = function(success)
        if success then
          request_dispatchers[path] = dispatch
        end
      end
      local params = {
        path = path,
        value = desc.value
      }
      service('add',params,assign_dispatcher,callbacks)
      local ref = {
        remove = function(ref,callbacks)
          assert(ref:is_added())
          self:remove(path,callbacks)
        end,
        is_added = function()
          return request_dispatchers[path] ~= nil
        end,
        add = function(ref,value,callbacks)
          assert(not ref:is_added())
          if value ~= nil then
            desc.value = value
          end
          self:add(desc,dispatch,callbacks)
        end,
        path = function()
          return path
        end
      }
      return ref
    end
    
    j.remove = function(_,path,callbacks)
      local params = {
        path = path
      }
      local remove_dispatcher = function(success)
        assert(success)
        request_dispatchers[path] = nil
      end
      service('remove',params,remove_dispatcher,callbacks)
    end
    
    j.call = function(self,path,params,callbacks)
      local params = {
        path = path,
        args = params or {}
      }
      service('call',params,nil,callbacks)
    end
    
    j.config = function(self,params,callbacks)
      service('config',params,nil,callbacks)
    end
    
    j.set = function(self,path,value,callbacks)
      local params = {
        path = path,
        value = value
      }
      service('set',params,nil,callbacks)
    end
    
    local fetch_id = 0
    
    j.fetch = function(self,params,f,callbacks)
      local id = '__f__'..fetch_id
      local sorting = params.sort
      fetch_id = fetch_id + 1
      local ref
      local add_fetcher = function()
        request_dispatchers[id] = function(peer,message)
          local params = message.params
          if not sorting then
            f(params.path,params.event,params.value,ref)
          else
            f(params.changes,params.n,ref)
          end
        end
      end
      if type(params) == 'string' then
        params = {
          path = {
            contains = params
          }
        }
      end
      params.id = id
      service('fetch',params,add_fetcher,callbacks)
      ref = {
        unfetch = function(_,callbacks)
          local remove_dispatcher = function()
            request_dispatchers[id] = nil
          end
          service('unfetch',{id=id},remove_dispatcher,callbacks)
        end,
        is_fetching = function()
          return request_dispatchers[id] ~= nil
        end,
        fetch = function(_,callbacks)
          service('fetch',params,add_fetcher,callbacks)
        end
      }
      return ref
    end
    
    j.method = function(self,desc,add_callbacks)
      local dispatch
      if desc.call then
        dispatch = function(self,message)
          local ok,result
          local params = message.params
          if #params > 0 then
            ok,result = pcall(desc.call,unpack(params))
          elseif pairs(params)(params) then
            -- non empty table
            ok,result = pcall(desc.call,params)
          else
            ok,result = pcall(desc.call)
          end
          local mid = message.id
          if mid then
            if ok then
              queue
              {
                id = mid,
                result = result or {}
              }
            else
              queue
              {
                id = mid,
                error = error_object(result)
              }
            end
          end
        end
      elseif desc.call_async then
        dispatch = function(self,message)
          local reply = function(resp,dont_flush)
            local mid = message.id
            if mid then
              local response = {
                id = mid
              }
              if type(resp.result) ~= 'nil' and not resp.error then
                response.result = resp.result
              elseif error then
                response.error = resp.error
              else
                response.error = 'jet.peer Invalid async method response '..desc.path
              end
              queue(response)
              if not will_flush and not dont_flush then
                flush('call_async')
              end
            end
          end
          
          local ok,result
          local params = message.params
          if #params > 0 then
            ok,result = pcall(desc.call_async,reply,unpack(params))
          elseif pairs(params)(params) then
            -- non empty table
            ok,result = pcall(desc.call_async,reply,params)
          else
            ok,result = pcall(desc.call_async,reply)
          end
          local mid = message.id
          if not ok and mid then
            queue
            {
              id = mid,
              error = error_object(result)
            }
          end
        end
      else
        assert(false,'invalid method desc'..(desc.path or '?'))
      end
      local ref = self:add(desc,dispatch,add_callbacks)
      return ref
    end
    
    j.state = function(self,desc,add_callbacks)
      local dispatch
      if desc.set then
        dispatch = function(self,message)
          local value = message.params.value
          local ok,result,dont_notify = pcall(desc.set,value)
          if ok then
            local newvalue
            if result ~= nil then
              newvalue = result
            else
              newvalue = value
            end
            desc.value = newvalue
            local mid = message.id
            if mid then
              queue
              {
                id = mid,
                result = true
              }
            end
            if not dont_notify then
              queue
              {
                method = 'change',
                params = {
                  path = desc.path,
                  value = newvalue
                }
              }
            end
          elseif message.id then
            queue
            {
              id = message.id,
              error = error_object(result)
            }
          end
        end
      elseif desc.set_async then
        dispatch = function(self,message)
          local value = message.params.value
          assert(value ~= nil,'params.value is required')
          local reply = function(resp,dont_flush)
            local mid = message.id
            if mid then
              local response = {
                id = mid
              }
              if resp.result ~= nil and not resp.error then
                response.result = resp.result
              elseif resp.error then
                response.error = error_object(resp.error)
              else
                response.error = 'jet.peer Invalid async state response '..desc.path
              end
              queue(response)
            end
            if resp.result and not resp.dont_notify then
              if resp.value ~= nil then
                desc.value = resp.value
              else
                desc.value = value
              end
              queue
              {
                method = 'change',
                params = {
                  path = desc.path,
                  value = desc.value
                }
              }
            end
            if not will_flush and not dont_flush then
              flush('set_aync')
            end
          end
          local ok,result = pcall(desc.set_async,reply,value)
          local mid = message.id
          if not ok and mid then
            queue
            {
              id = mid,
              error = error_object(result)
            }
          end
        end
      else
        dispatch = function(self,message)
          local mid = message.id
          if mid then
            queue
            {
              id = mid,
              error = invalid_params()
            }
          end
        end
      end
      local ref = self:add(desc,dispatch,add_callbacks)
      ref.value = function(self,value)
        if value ~= nil then
          desc.value = value
          queue
          {
            method = 'change',
            params = {
              path = desc.path,
              value = value
            }
          }
          if not will_flush then
            flush()
          end
        else
          return desc.value
        end
      end
      return ref
    end
    
    local cmsgpack
    if config.encoding then
      if config.encoding ~= 'msgpack' then
        error('unsupported encoding')
      end
      cmsgpack = require'cmsgpack'
    end
    
    if config.persist then
      table.insert(try,function(step)
          if not persist_id then
            j:config({persist=config.persist},{
                success = function(pid)
                  persist_id = pid
                  is_persistant = true
                  step.success()
                end,
                error = function(err)
                  step.error(err)
                end
            })
          else
            j:config({resume={
                  id = persist_id,
                  receivedCount = received_count
                }},{
                success = function(received_by_daemon_count)
                  flush('resume')
                  pending = false
                  is_persistant = true
                  local missed_messages_count = message_count - received_by_daemon_count
                  local history = message_history
                  -- the last message in history is "config.resume"
                  -- skip that!
                  local start = #history-missed_messages_count-1
                  local stop = #history-1
                  if start < 0 then
                    step.error(internal_error(historyNotAvailable))
                  end
                  local missed = {}
                  for i=start,stop do
                    tinsert(missed,history[i])
                  end
                  if #missed > 0 then
                    wsock:send(encode(missed))
                  end
                  step.success()
                end,
                error = function(err)
                  step.error(err)
                end
            })
          end
        end)
      
    end
    
    if config.name then
      table.insert(try,function(step)
          j:config({name=config.name},step)
          flush('name')
        end)
    end
    
    if config.encoding then
      table.insert(try,function(step)
          j:config({encoding=config.encoding},{
              success = function()
                flush('encoding')
                if config.encoding then
                  encode = cmsgpack.pack
                  decode = cmsgpack.unpack
                end
                step.success()
              end,
              error = function(err)
                step.error(err)
              end
          })
        end)
    end
    
    connect_sequence = step.new({
        try = try,
        catch = function(err)
          if not config.persist then
            j:close()
          end
        end,
        finally = function()
          if config.on_connect then
            config.on_connect(j)
            config.on_connect = nil
          end
          flush('on_connect')
        end
    })
    
    
    wsock:on_connect(function()
        connect_sequence()
        flush('config')
      end)
    
    wsock:connect()
    
    return j
  end
end

return {
  new = new
}


