#!/usr/bin/env lua
local cjson = require'cjson'
local tinsert = table.insert
local ev = require'ev'
local websockets = require'websockets'
local wsWRITE_TEXT = websockets.WRITE_TEXT
local ws_ios = {}
local ws_context = nil
local log = 
   function(...)
      print('zbus-websocket-bridge',...)
   end
local exit = 
   function()
      for fd,io in pairs(ws_ios) do
	 io:stop(ev.Loop.default)
      end
      ws_context:destroy()
   end
local clients = 0

ws_context = websockets.context{
   port = arg[1] or 8004,
   on_add_fd = 
      function(fd)	
         assert(fd > -1)
	 local io = ev.IO.new(
	    function()
	       ws_context:service(0)
	    end,fd,ev.READ)
	 ws_ios[fd] = io
	 io:start(ev.Loop.default)
      end,
   on_del_fd = 
      function(fd)
         assert(fd > -1)
	 ws_ios[fd]:stop(ev.Loop.default)
	 ws_ios[fd] = nil
      end,
   protocols = {
      ['ping'] = 
        function(ws)
          ws:on_receive(
            function(ws,data)
              ws:write('pong',wsWRITE_TEXT)              
            end)
        end,
      ['jet'] =
         function(ws)	  
            clients = clients + 1
            local jeti = require'jet'.new{name='jet-websocket-bridge'..clients}
            local io = jeti.zbus:listen_io()
            io:start(ev.Loop.default)
            ws:on_closed(
               function()
                  clients = clients - 1
                  io:stop(ev.Loop.default)
                  jeti.zbus:close()
               end)
            ws:on_receive(
      	       function(ws,data)
		  local req = cjson.decode(data)
		  local resp = {id=req.id}
                  local method = req.method
                  if method == 'fetch' then
                     local notifications = {}
                     jeti:fetch(
                        '.*',
                        function(url_event,more,data)
                           local url,event = url_event:match('^(.*):(%w+)$')
                           local n = {
                              method = url_event,
                              params = {data}
                           }
                           tinsert(notifications,n)
                           if not more then
                              ws:write(cjson.encode(notifications),wsWRITE_TEXT)
                              notifications = {}
                           end
                        end                        
                     )
                  elseif jeti[method] then
                     local result = {pcall(jeti[method],jeti,unpack(req.params))}
                     if result[1] then 
                        table.remove(result,1);
                        resp.result = result
                     else
                        resp.error = result[2]
                     end
                  else
                     resp.error = {
                        code = -32601,
                        messgae = 'Method not found',
                        data = method
                     }
                  end
      		  ws:write(cjson.encode(resp),wsWRITE_TEXT)
      	       end)
         end        
   }      
}

ev.Loop.default:loop()


