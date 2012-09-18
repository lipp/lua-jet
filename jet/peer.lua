local jsocket = require'jet.socket'
local socket = require'socket'
local ev = require'ev'
local cjson = require'cjson'
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local type = type
local error = error
local print = print
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local unpack = unpack
local assert = assert
local log = function(...)
   print('jet.peer',...)
end

module('jet.peer')

local error_object = function(err)
   local error
   if type(err) == 'table' and err.code and err.message then
      error = err
   else
      error = {
         code = -32602,
         message = 'Internal error',
         data = err,
      }
   end   
   return error
end

new = function(config)   
   config = config or {}
   local ip = config.ip or 'localhost'
   local port = config.port or 33326
   local loop = config.loop or ev.Loop.default
   local sock = socket.connect(ip,port)
   if not sock then
      error('could not connect to jetd with ip:'..ip..' port:'..port)
   end
   local request_dispatchers = {}
   local response_dispatchers = {}
   local dispatch_response = function(self,message)
      local callbacks = response_dispatchers[message.id]
      response_dispatchers[message.id] = nil
      --      log('response',cjson.encode(message),callbacks,message.result,message.error)
      if callbacks then
         if message.result then
            if callbacks.success then
               --            log('response','success',message.id)       
               callbacks.success(message.result)
            end
         elseif message.error then
            if callbacks.error then
               --            log('response','error',message.id)       
               callbacks.error(message.error)
            end
         else
            log('invalid result:',cjson.encode(message))
         end
      else
         log('invalid result id:',id)
      end
   end
   local dispatch_notification = function(self,message)
      local dispatcher = request_dispatchers[message.method]
      if dispatcher then
         --         log('NOTIF',cjson.encode(message))
         local ok,err = pcall(dispatcher,self,message)
         if not ok then
            log('fetcher:'..message.method,'failed:'..err,cjson.encode(message))
         end
      end
      --log('notification',cjson.encode(message))
   end
   local dispatch_request = function(self,message)
      --      log('dispatch_request',self,cjson.encode(message))
      local dispatcher = request_dispatchers[message.method]
      if dispatcher then
         local error
         --      log('dispatch_call',method_name,method)
         local ok,err = pcall(dispatcher,self,message)
         if ok then
            return 
         else
            error = error_object(err)
         end     
      else
         error = {
            code = -32601,
            message = 'Method not found'
         }         
      end
      sock:send
      {
         id = message.id,
         error = error
      }
   end
   local dispatch_single_message = function(self,message)      
      if message.id then
         if message.method and message.params then
            dispatch_request(self,message)
         elseif message.result or message.error then
            dispatch_response(self,message)
         else
            log('unhandled message',cjson.encode(message))
         end
      elseif message.method and message.params then
         dispatch_notification(self,message)
      else
         log('unhandled message',cjson.encode(message))
      end
   end
   local dispatch_message = function(self,message,err)
      if message then
         if #message > 0 then
            for i,message in ipairs(message) do
               dispatch_single_message(self,message)
            end
         else
            dispatch_single_message(self,message)
         end
      else      
         self:send
         {
            error = {
               code  = -32700,
               messsage = 'Parse error'
            }
         }
      end
   end
   local args = {
      on_message = dispatch_message,
      on_error = log,
      on_close = log,
      loop = loop
   }
   sock = jsocket.wrap(sock,args)
   local j = {}

   j.io = function()
      return sock:read_io()
   end

   j.loop = function()
      sock:read_io():start(loop)
      loop:loop()
   end

   j.close = function()
      sock:shutdown()
      sock:close()      
   end

   local id = 0
   local batch = {}
   local batching
   service = function(method,params,complete,callbacks)
      local rpc_id
      -- Only make a Request, if callbacks are specified.
      -- Make complete call in case of success.      
      -- If no id is specified in the message, no Response 
      -- is expected, aka Notification.
      if callbacks then
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
      if batching then
         log('batching',cjson.encode(message))
         tinsert(batch,message)
      else
         log('sendinf',cjson.encode(message))
         sock:send(message)
      end
   end

   j.batch = function(self,action)
      batching = true
      action()
      batching = false
      log('TATA',cjson.encode(batch))
      sock:send(batch)
      batch = {}
   end

   j.add = function(self,path,el,dispatch,callbacks)
      assert(not request_dispatchers[path])
      assert(type(path) == 'string')
      assert(type(el) == 'table')
      assert(type(dispatch) == 'function')
      local assign_dispatcher = function(success)
         log('assigned',path)
         request_dispatchers[path] = dispatch
      end
      local params = {
         path = path,
         element = el
      }
      service('add',params,assign_dispatcher,callbacks)   
   end

   j.remove = function(_,path,callbacks)
      local params = {
         path = path
      }
      service('remove',params,nil,callbacks)
   end

   j.call = function(self,path,params,callbacks)
      local params = {
         path = path,
         args = params
      }      
      service('call',params,nil,callbacks)
   end

   j.notify = function(self,notification,callbacks)
      assert(notification.path)
      assert(notification.event)
      assert(notification.data)
      service('notify',notification,nil,callbacks)
   end

   j.fetch = function(self,id,expr,f,callbacks)
      local add_fetcher = function()
         request_dispatchers[id] = function(peer,message)
            f(message.params)
         end
      end      
      local params = {
         id = id,
      }
      if type(expr) == 'string' then
         params.match = {expr}
      else
         params.match = expr.match
         params.unmatch = expr.unmatch
      end
      service('fetch',params,add_fetcher,callbacks)
   end

   j.method = function(self,desc,callbacks)
      local el = {}
      el.type = 'method'
      el.schema = desc.schema
      local dispatch
      if not desc.async then         
         dispatch = function(self,message)
            local ok,result = pcall(desc.call,self,unpack(message.params))
            if message.id then
               if ok then
                  self:send
                  {
                     id = message.id,
                     result = result or {}
                  }
               else               
                  self:send
                  {
                     id = message.id,
                     error = error_object(result)
                  }
               end
            end
         end
      else
         dispatch = function(self,message)
            desc.call(self,message)
         end
      end
      
      self:add(desc.path,el,dispatch,callbacks)
      local ref = {         
         remove = function(_,callbacks)
            log('removing',desc.path)
            self:remove(desc.path,callbacks)
         end,
         add = function(_,callbacks)
            log('adding',desc.path)
            self:add(desc.path,el,callbacks)
         end
      }
      return ref
   end

   j.state = function(self,desc,callbacks)
      local el = {}
      el.type = 'state'
      el.schema = desc.schema
      el.value = desc.value
      local dispatch
      if not desc.async then         
         dispatch = function(self,message)
            local value = message.params.value
            local ok,result,dont_notify = pcall(desc.set,self,value)
            if ok then
               local messages = {}
               messages[1] = {
                  id = message.id,
                  result = result or {}
               }
               if not dont_notify then
                  messages[2] = {
                     method = 'change',
                     params = {
                        value = result or value
                     }
                  }
               end
               self:send(messages)
            else
               self:send
               {
                  id = message.id,
                  error = error_object(result)
               }
            end
         end
      else
         assert(nil,'async states not supported yet')
      end
      self:add(desc.path,el,dispatch,callbacks)
   end
   return j
end

return {
   new = new
       }


