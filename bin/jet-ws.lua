#!/usr/bin/env lua
-- This process allows to connect via websocket protocol
-- to a local running jet.
--
-- Messages are simple forwarded to/from jet, no further
-- interpretation takes place.
-- usage: ./lua-ws 8004 33326

local ws_port = arg[1] or 8004
local jet_port = arg[2] or 33326

local socket = require'socket'
local ev = require'ev'
local websockets = require'websockets'

local ios = {}
local context = nil
local log = function(...)
   print('jet-ws',...)
end

local exit = function()
   for fd,io in pairs(ios) do
      io:stop(ev.Loop.default)
   end
   context:destroy()
end

context = websockets.context
{
   port = ws_port,
   on_add_fd = function(fd)	
      assert(fd > -1)
      local io = ev.IO.new(
         function()
            context:service(0)
         end,fd,ev.READ)
      ios[fd] = io
      io:start(ev.Loop.default)
   end,
   on_del_fd = function(fd)
      assert(fd > -1)
      ios[fd]:stop(ev.Loop.default)
      ios[fd] = nil
   end,
   protocols = {
      jet = function(ws)	  
         local jet_sock = socket.connect('localhost',jet_port)
         local io
         assert(jet_sock)
         local args = {
            loop = ev.Loop.default,
            dont_encode = true,
            dont_decode = true,
            on_message = function(sock,json)
               ws:write(json)
            end,
            on_close = function()
               ws:close()
            end,
            on_error = function()
               ws:close()
            end
         }
         jet_sock = require'jet.socket'.wrap(jet_sock,args)
         io = jet_sock.read_io()
         io:start(ev.Loop.default)
         ws:on_closed(
            function()
               io:stop(ev.Loop.default)
               jet_sock:close()
            end)
         ws:on_receive(
            function(ws,json)
               jet_sock:send(json)
            end)
      end        
      }      
}

log('starting jet websocket bridge')
log('assuming jet on port:',jet_port)
log('listening for websocket connects on port:',ws_port)

-- infinitely wait / dispatch events
ev.Loop.default:loop()


