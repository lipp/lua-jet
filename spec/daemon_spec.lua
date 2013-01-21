require'busted'
package.path = package.path..'../'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local loop = ev.Loop.default
local port = 12349

describe(
   'A daemon', 
   function()
      local d
      before(
         function()
            d = jetdaemon.new
            {
               port = port
            }
         end)

      it(
         'provides the correct interface',
         function()
            assert.is_true(type(d) == 'table')
            assert.is_true(type(d.start) == 'function')
            assert.is_true(type(d.stop) == 'function')
         end)

      it(
         'can be started',
         function()
            assert.has_not_error(
               function()
                  d:start()
               end)
         end)

      it(
         'can be stopped',
         function()
            assert.has_not_error(
               function()
                  d:stop()
               end)
         end)
      
      describe(
         'once started',
         function()
            before(
               function()
                  d:start()
               end)
            
            after(
               function()
                  d:stop()
               end)
            
            it(
               'listens on specified port',
               async,
               function(done)
                  local sock = socket.connect('localhost',port)
                  sock:settimeout(0)
                  ev.IO.new(
                     function(loop,io)
                        io:stop(loop)
                        assert.is_true(true)
                        done()
                     end,sock:getfd(),ev.WRITE):start(loop)
               end)
         end)
end)

return function()
   loop:loop()
       end

