require'busted'
package.path = package.path..'../'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = 12350

describe(
   'A peer', 
   function()
      local d
      local peer
      before(
         function()
            d = jetdaemon.new
            {
               port = port
            }
            d:start()
         end)

      after(
         function()
            d:stop()
         end)

      it(
         'provides the correct interface',
         function()
            local peer = jetpeer.new{ port = port }
            assert.is_true(type(peer) == 'table')
            assert.is_true(type(peer.state) == 'function')
            assert.is_true(type(peer.method) == 'function')
            assert.is_true(type(peer.call) == 'function')
            assert.is_true(type(peer.set) == 'function')
            assert.is_true(type(peer.notify) == 'function')
            assert.is_true(type(peer.fetch) == 'function')
            assert.is_true(type(peer.batch) == 'function')
            assert.is_true(type(peer.loop) == 'function')
            peer:io():stop(loop)
         end)

      it(
         'on_connect gets called',
         async,
         function(done)
            local timer
            local peer
            peer = jetpeer.new
            { 
               port = port,
               on_connect = function(p)
                  assert.is_equal(peer,p)
                  timer:stop(loop)
                  peer:io():stop(loop)
                  done()
               end
            }
            timer = ev.Timer.new(
               function()
                  assert.is_true(false)
               end,0.1)
            timer:start(loop)
         end)
end)

return function()
   loop:loop()
       end

