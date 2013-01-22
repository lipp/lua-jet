package.path = package.path..'../'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT')
require'busted'

describe(
   'A peer', 
   function()
      local d
      local peer
      before(
         function()
            d = jetdaemon.new{port = port}
            d:start()
         end)

      after(
         function()
            d:stop()
         end)

      it(
         'provides the correct interface',
         function()
            local peer = jetpeer.new{port = port}
            assert.is_true(type(peer) == 'table')
            assert.is_true(type(peer.state) == 'function')
            assert.is_true(type(peer.method) == 'function')
            assert.is_true(type(peer.call) == 'function')
            assert.is_true(type(peer.set) == 'function')
            assert.is_true(type(peer.notify) == 'function')
            assert.is_true(type(peer.fetch) == 'function')
            assert.is_true(type(peer.batch) == 'function')
            assert.is_true(type(peer.loop) == 'function')
            peer:close()
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
               on_connect = continue(
                  function(p)
                     assert.is_equal(peer,p)
                     timer:stop(loop)
                     peer:close()
                     done()
                  end)
            }
            timer = ev.Timer.new(
               continue(
                  function()
                     assert.is_true(false)
                  end),0.1)
            timer:start(loop)
         end)

      describe(
         'when connected',
         function()
            local peer
            local path = 'test'
            local value = 1234
            before(
               async,
               function(done)
                  peer = jetpeer.new
                  { 
                     port = port,
                     on_connect = continue(
                        function(p)
                           done()
                        end)
                  }
               end)

            after(
               function()
                  peer:close()
                  peer:io():stop(loop)
               end)

            it(
               'can add states',
               async,
               function(done)

                  local timer
                  peer:state(
                     {
                        path = path,
                        value = value
                     },
                     {
                        success = continue(
                           function()                           
                              timer:stop(loop)
                              assert.is_true(true)
                              done()
                           end)
                     })
                  timer = ev.Timer.new(
                     continue(
                        function()
                           assert.is_true(false)
                           done()
                        end),0.1)
                  timer:start(loop)
               end)

            it(
               'can not add same state again',
               function()
                  assert.has_error(
                     function()
                        peer:state
                        {
                           path = path,
                           value = value
                        }                       
                     end)
               end)
            
            it(
               'can fetch states',
               async,
               function(done)
                  local timer
                  peer:fetch(
                     path,
                     continue(
                        function(fpath,fevent,fdata,fetcher)
                           timer:stop(loop)
                           assert.is_equal(fpath,path)
                           assert.is_equal(fdata.value,value)
                           fetcher:unfetch()
                           done()
                        end))
                  timer = ev.Timer.new(
                     continue(
                        function()
                           assert.is_true(false)
                           done()
                        end),0.1)
                  timer:start(loop)
               end)
         end)
end)

return function()
   loop:loop()
       end

