#!/usr/bin/env lua
local socket = require'socket'
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
            local jet_sock = socket.connect('localhost',33326)
            local io
            assert(jet_sock)
            local args = {
               loop = ev.Loop.default,
               dont_encode = true,
               dont_decode = true,
               on_message = function(sock,message)
                  log('<=',message)
                  ws:write(message,wsWRITE_TEXT)
               end,
               on_close = function()
                  clients = clients - 1
                  assert(clients >= 0)
                  ws:close()
               end,
               on_error = function()
                  clients = clients - 1
                  assert(clients >= 0)
                  ws:close()
               end
            }
            local jet_sock = require'jet.socket'.wrap(jet_sock,args)
            io = jet_sock.read_io()
            io:start(ev.Loop.default)
            ws:on_closed(
               function()
                  clients = clients - 1
                  io:stop(ev.Loop.default)
                  jet_sock:close()
               end)
            ws:on_receive(
      	       function(ws,data)
                  log('=>',data)
                  -- send data and dont encode to JSON (already is supposed to be JSON)
                  jet_sock:send(data,true)
      	       end)
         end        
   }      
}

ev.Loop.default:loop()


