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
   print('jet.client',...)
end

module('jet.client')

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
   local method_dispatchers = {}
   local response_dispatchers = {}
   local dispatch_response = function(self,message)
      local callbacks = response_dispatchers[message.id]
      response_dispatchers[message.id] = nil
--      log('response',cjson.encode(message),callbacks,message.result,message.error)
      if callbacks then
         if message.result then
--            log('response','success',message.id)       
            callbacks.success(message.result)
         elseif message.error then
--            log('response','error',message.id)       
            callbacks.error(message.error)
         else
            log('invalid result:',cjson.encode(message))
         end
      else
         log('invalid result id:',id)
      end
   end
   local dispatch_notification = function(self,message)
      local dispatcher = method_dispatchers[message.method]
      if dispatcher then
--         log('NOTIF',cjson.encode(message))
         local ok,err = pcall(dispatcher,self,message)
         if not ok then
            log('fetcher:'..message.method,'failed:'..err,cjson.encode(message))
         end
      end
      --log('notification',cjson.encode(message))
   end
   -- local dispatch_result = function(self,message)
   --    local callbacks = response_dispatchers[message.id]
   --    if callbacks then
   --       callbacks.success(message.result)
   --    else
   --       log('invalid result id:',id)
   --    end
   -- end
   local dispatch_request = function(self,message)
--      log('dispatch_request',self,cjson.encode(message))
      local dispatcher = method_dispatchers[message.method]
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
--      log('dispatch_single_message',cjson.encode(message))
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

   local id = 0
   local batch = {}
   local batching
   send = function(method,params,callbacks)
      local rpc_id
      if callbacks then
         id = id + 1
         rpc_id = id
         response_dispatchers[id] = callbacks
      end
      local message = {
         id = rpc_id,
         method = method,
         params = params
      }
      if batching then
         tinsert(batch,message)
      else
         sock:send(message)
      end
   end

   j.batch = function(self,action)
      batching = true
      action()
      sock:send(batch)
      batch = {}
      batching = false
   end

   j.add = function(self,path,el,callbacks)
      local dispatch = el.dispatch
      el.dispatch = nil
      assert(not method_dispatchers[path])
      method_dispatchers[path] = dispatch
      send('add',{path,el},callbacks)   
   end

   j.call = function(self,path,params,callbacks)
      params = params or {}
      tinsert(params,1,path)
--      print('CBS'
      send('call',params,callbacks)
   end

   j.notify = function(self,notification,callbacks)
      send('notify',notification,callbacks)
   end

   j.fetch = function(self,id,expr,f,callbacks)
      local f_strip_client = function(client,...)
         f(...)
      end
      if callbacks then
         local add_fetcher = function()
--            log('add fetcher')
            method_dispatchers[id] = f_strip_client
         end        
         if callbacks.success then
            local old = callbacks.success
            callbacks.success = function(...)
               add_fetcher()
               old(...)
               callbacks.success = old
            end
         else
            callbacks.success = add_fetcher
         end
      else
         method_dispatchers[id] = f_strip_client
      end
      send('fetch',{id,expr},callbacks)
   end

   j.remove = function(path,callbacks)
      rpc('remove',{path},callbacks)
   end

   j.method = function(desc)
      local el = {}
      el.type = 'method'
      el.schema = desc.schema
      if not desc.async then         
         el.dispatch = function(self,message)
--            log('method dispatch',cjson.encode(message))
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
         el.dispatch = function(self,message)
            desc.call(self,message)
         end
      end
      return el
   end

   j.state = function(desc)
      local el = {}
      el.type = 'state'
      el.schema = desc.schema
      el.value = desc.value
      if not desc.async then         
         el.dispatch = function(self,message)
            local value = message.params[1]
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
      return el
   end
   return j
end

return {
   new = new
       }


