require'busted'
package.path = package.path..'../'

local ev = require'ev'
local socket = require'socket'
local jetsocket = require'jet.socket'
local loop = ev.Loop.default
local port = 12349

local echo_listener = assert(socket.bind('*',port))
local accept_echo = function()
   local sock = echo_listener:accept()
   local io = jetsocket.wrap(
      sock,{
         loop = loop,
         on_message = function(wrapped,message)
            wrapped:send(message)
         end,
         on_close = function() end,
         on_error = function() end
           }):read_io()
   io:start(loop)
end
echo_listener:settimeout(0)
local echo_server_io = ev.IO.new(
   accept_echo,
   echo_listener:getfd(),
   ev.READ)

describe(
   'A message socket', 
   function()
      before(
         function()
            echo_server_io:start(loop)
         end)

      after(
         function()
            echo_server_io:stop(loop)
         end)

      describe(
         'when connecting to echo server',
         function()
            local sock
            before(
               function()
                  sock = socket.connect('localhost',port)
               end)

            after(
               function()
                  sock:close()
               end)

            it(
               'can echo messages',
               async,
               function(done)
                  local message = {
                     1,2,3
                  }
                  local wrapped = jetsocket.wrap(
                     sock,{
                        on_message = function(wrapped,echoed)
                           assert.is.same(message,echoed)
                           done()                                                
                        end,
                        loop = loop,
                        on_close = function() end,
                        on_error = function() end
                          })
                  wrapped:read_io():start(loop)
                  wrapped:send(message)                     
               end)           
         end)
   end)

return 'ev',loop

