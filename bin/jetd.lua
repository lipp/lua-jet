#!/usr/bin/env lua

local cjson = require'cjson'
local ev = require'ev'
local socket = require'socket'
local jsocket = require'jet.socket'
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
--local jcache = require'jet.cache'

local port = 33326
local loop = ev.Loop.default

local log = function(...)
   print('jetd',...)
end

local invalid_params = function(data)
   local err = {
      code = -32602,
      message = 'Invalid params',
      data = data
   }
   return err
end

-- holds all (jet.socket.wrapped) clients index by client itself
local clients = {}
local nodes = {}
local states = {}
local methods = {}
local routes = {}

local route_message = function(client,message)
   local route = routes[message.id]
   if route then
      routes[message.id] = nil
      message.id = route.id
      route.receiver:send(message)      
   else
      log('unknown route id:',cjson.encode(message))
   end
end

local post = function(notification)
   local path = notification.path
   --   print('POST',notification.path,notification.event)
   for client in pairs(clients) do      
      --      print('POST',client,'?')
      for fetch_id,matcher in pairs(client.fetchers) do
         --         print('POST',fetch_id,'?')
         if matcher(path) then
            --            print('MATCH',path,fetch_id)
            if not client.notifications then
               client.notifications = {}
            end
            local notification = {
               method = fetch_id,
               params = notification
            }
            tinsert(client.notifications,notification)
         end
      end
   end
end

local flush = function()
   --   print('FLUSHING')
   for client in pairs(clients) do
      if client.notifications and #client.notifications > 0 then
         client:send(client.notifications)
         client.notifications = nil
      end
   end
end

local matcher = function(config)
   local f
   if type(config) == 'string' then
      f = function(path)
         return path:match(config)
      end
   end
   if config.match and config.unmatch then
      if type(config.match) == 'table' and #config.match > 0 then
         f = function(path)
            for _,unmatch in ipairs(config.unmatch) do               
               if path:match(unmatch) then
                  return false
               end
            end
            for _,match in ipairs(config.match) do
               if path:match(match) then
                  return true
               end
            end
         end         
      end
   end
   assert(f and type(f) == 'function')
   return f
end

local notify = function(client,message)
   local notification = message.params
   local path = notification.path
   local error
   local state = states[path]
   if state then
      if notification.event == 'change' then
         for k,v in pairs(notification.data) do
            state.element[k] = v
         end
      end
      post(notification)
   elseif methods[path] then
      local method = methods[path]
      if notification.event == 'change' then
         for k,v in pairs(notification.data) do
            method.element[k] = v
         end
      end
      post(notification)
   else
      error = {
         code = 123,
         message 'invalid path',
         data = path
      }
      if message.id then
         client:send
         {
            id = message.id,
            error = error
         }
      else
         log('notify failed',cjson.encode(message))
      end   
   end
end

local fetch = function(client,message)
   if #message.params == 2 then
      local id = message.params[1]
      local matcher = matcher(message.params[2]) 
      if not client.fetchers[id] then
         if not client.notifications then
            client.notifications = {}
         end
         local node_notifications = {}
         for path in pairs(nodes) do
            if matcher(path) then
               local notification = {                  
                  method = id,
                  params = {
                     path = path,
                     event = 'add',  
                     data = {
                        type = 'node'
                     }
                  }
               }
               tinsert(node_notifications,notification)
            end
         end
         local compare_path_length = function(not1,not2)
            return #not1.params.path < #not2.params.path
         end
         table.sort(node_notifications,compare_path_length)
         for _,notification in ipairs(node_notifications) do
            tinsert(client.notifications,notification)
         end
         for path,method in pairs(methods) do
            if matcher(path) then
               local notification = {
                  method = id,
                  params = {
                     path = path,
                     event = 'add',
                     data = method.element
                  }
               }
               tinsert(client.notifications,notification)
            end
         end
         for path,states in pairs(states) do
            if matcher(path) then
               local notification = {
                  method = id,
                  params = {
                     path = path,
                     event = 'add',
                     data = {
                        type = 'state',      
                        --                        schema = method.element.schema,
                        --                        value = method.element.value
                     }            
                  }
               }
               tinsert(client.notifications,notification)
            end
         end
         --         client:send(notifications)
      end
      client.fetchers[id] = matcher
      if message.id then
         client:send
         {
            id = message.id,
            result = {}
         }
      end
   else
      if message.id then
         local error = invalid_params{expected = '[fetch_name,expression] or [fetch_name,{"match":[...],"unmatch":[...]}',got = '[]'}
         client:send
         {
            id = message.id,
            error = error
         }
      end
   end
end

local call = function(client,message)
   if #message.params > 0 then
      local path = message.params[1]
      --   log('call',path)
      if methods[path] then
         tremove(message.params,1)
         --      log('call',path,'method found')
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
         --      table.remove(message.params,1)
         methods[path].client:send
         {
            id = id, -- maybe nil
            method = path,
            params = message.params
         }
      elseif message.id then
         client:send
         {
            id = message.id, 
            error = {
               code = 123,
               message = 'jet method unknown',
               data = path
            }
         }
      end
   else
      local error = invalid_params{expected = '[path,...]',got = '[]'}
      client:send
      {
         id = message.id,
         error = error
      }
   end
end

local increment_nodes = function(path)
   local parts = {}
   for part in path:gmatch('[^/]+') do
      tinsert(parts,part)
   end
   for i=1,#parts-1 do 
      local path = tconcat(parts,'/',1,i)
      local count = nodes[path]
      if count then
         nodes[path] = count+1
      else
         print('new node',path) 
         nodes[path] = 1
         post
         {
            event = 'add',
            path = path,
            data = {
               type = 'node'
            }
         }
      end
      print('node',node,nodes[path])
   end   
end

local decrement_nodes = function(path)
   local parts = {}
   for part in path:gmatch('[^/]+') do
      tinsert(parts,part)
   end
   for i=1,#parts-1 do 
      local path = tconcat(parts,'/',1,i)
      local count = nodes[path]
      if count > 1 then
         nodes[path] = count-1
         print('node',path,nodes[path])
      else
         nodes[path] = nil
         print('delete node',path)
         post
         {
            event = 'remove',
            path = path,
            data = {
               type = 'node'
            }
         }
      end
   end   
end


local add = function(client,message)
--   print('ADD',cjson.encode(message))
   if #message.params == 2 then
      local path = message.params[1]
      if nodes[path] or states[path] or methods[path] then
         error(invalid_params{occupied = path})
      end
      increment_nodes(path)
      local element = message.params[2]
      local method = {
         client = client,
         element = element
      }
      methods[path] = method
      post
      {
         path = path,
         event = 'add',
         data = element
      }
   else
      error(invalid_params{expected = '[path,element]',got = message.params})
   end
end

local remove = function(client,message)
   if #message.params == 1 then
      local path = message.params[1]
      if not states[path] and not methods[path] then
         error(invalid_params{invalid_path = path})
      end
      decrement_nodes(path)
      local el = methods[path].element
      methods[path] = nil
      post
      {
         path = path,
         event = 'remove',
         data = el
      }
      --      cache.add(client,path,element)
   else
      error(invalid_params{expected = '[path]',got = message.params})
   end
end

local sync = function(f)
   local sc = function(client,message)
      local ok,result = pcall(f,client,message)
      if message.id then
         if ok then
            client:send
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
            client:send
            {
               id = message.id,
               error = error
            }
         end
      elseif not ok then
         log('sync '..message.method..' failed',cjson.encode(result))
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
            client:send
            {
               id = message.id,
               error = err
            }
         end
      elseif not ok then
         log('async '..message.method..' failed:',cjson.encode(err))
      end
   end
   return ac
end

local services = {
   add = sync(add),   
   call = async(call),   
   fetch = async(fetch),
   notify = sync(notify),
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
   client:send
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
         log('dispatch_notification error:',cjson.encode(err))
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
         client:send
         {
            id = message.id,
            error = {
               code = -32600,
               message = 'Invalid Request',
               data = message
            }
         }
         log('message not dispatched:',cjson.encode(message))
      end  
   elseif message.method then
      dispatch_notification(client,message)
   else
      log('message not dispatched:',cjson.encode(message))
   end
end

local dispatch_message = function(client,message,err)
   if message then
      if #message > 0 then
         for i,message in ipairs(message) do
            dispatch_single_message(client,message)
         end
      else
         dispatch_single_message(client,message)
      end
      flush()
   else      
      client:send
      {
         error = {
            code  = -32700,
            messsage = 'Parse error'
         }
      }
   end
end

--local clients = {}

local listener = assert(socket.bind('*',port))
local accept_client = function(loop,accept_io)
   local client = listener:accept()
   if not client then
      log('accepting client failed')
      return 
   end
   local release_client = function(client)
      --      log('releasing',client)
      client.fetchers = {}
      for path,method in pairs(methods) do
         if method.client == client then
            post
            {
               event = 'remove',
               path = path,
               data = {
                  type = 'node'
               }
            }
            decrement_nodes(path)
            methods[path] = nil
         end
      end
      flush()
      client:close()
      clients[client] = nil
   end
   local args = {
      loop = loop,
      on_message = dispatch_message,
      on_close = release_client,
      on_error = log
   }
   local wrapped = jsocket.wrap(client,args)
   wrapped.fetchers = {}
   wrapped:read_io():start(loop)
   clients[wrapped] = wrapped
end

listener:settimeout(0)
local listen_io = ev.IO.new(
   accept_client,
   listener:getfd(),
   ev.READ)
listen_io:start(loop)

for _,opt in ipairs(arg) do
   if opt == '-d' or opt == '--daemon' then      
      local ffi = require'ffi'
      if not ffi then
         log('daemonizing failed: ffi (luajit) is required.')
         os.exit(1)
      end
      ffi.cdef'int daemon(int nochdir, int noclose)'
      assert(ffi.C.daemon(1,1)==0)      
   end
end

loop:loop()



