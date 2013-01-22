require'busted'
package.path = package.path..'../'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT') or 33326

describe(
   'A daemon', 
   function()
      local daemon
      before(
         function()
            daemon = jetdaemon.new
            {
               port = port
            }
         end)

      it(
         'provides the correct interface',
         function()
            assert.is_true(type(daemon) == 'table')
            assert.is_true(type(daemon.start) == 'function')
            assert.is_true(type(daemon.stop) == 'function')
         end)

      it(
         'can be started',
         function()
            assert.has_not_error(
               function()
                  daemon:start()
               end)
         end)

      it(
         'can be stopped',
         function()
            assert.has_not_error(
               function()
                  daemon:stop()
               end)
         end)
      
      describe(
         'once started',
         function()
            before(
               function()
                  daemon:start()
               end)
            
            after(
               function()
                  daemon:stop()
               end)
            
            it(
               'listens on specified port',
               async,
               function(done)
                  local sock = socket.connect('127.0.0.1',port)
                  assert.is_truthy(sock)
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

