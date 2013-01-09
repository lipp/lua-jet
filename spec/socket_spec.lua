require('busted')
package.path = package.path..'../'

local ev = require'ev'
local socket = require'socket'
local jetsocket = require'jet.socket'
local loop = ev.Loop.default
local port = 12349

describe(
   'The object returned by jet.socket.wrap_async', 
   function()
      setup(
         function()
            local echo_listener = assert(socket.bind('*',port))
            local accept_echo = function()
               local sock = echo_listener:accept()
               local wrapped = jetsocket.wrap_async(
                  sock,{
                     on_message = function(wrapped,...)
                        print('echoing',...)
                        wrapped:send({...})
                     end
                       })
            end
            echo_listener:settimeout(0)
            ev.IO.new(accept_echo,echo_listener:getfd(),ev.READ):start(loop)
         end)
      it(
         'should be thoroughly testes', 
         function()
            ev.Timer.new(
               function() 
                  assert.is_true(false)
               end,0.1):start(loop)
            
--            loop()
         end)
      teardown(
         function()
            loop:unloop()
         end)
      loop:loop()
   end)

