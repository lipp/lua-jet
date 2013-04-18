local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT')

setloop('ev')

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
        assert.is_true(type(peer.on_no_dispatcher) == 'function')
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
          on_connect = guard(
            function(p)
              assert.is_equal(peer,p)
              timer:stop(loop)
              peer:close()
              done()
            end)
        }
        timer = ev.Timer.new(
          guard(
            function()
              peer:close()
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
              on_connect = guard(
                function(p)
                  done()
                end)
            }
          end)
        
        after(
          function()
            peer:close()
          end)
        
        local some_state
        
        it(
          'can add states',
          async,
          function(done)
            local timer
            peer:on_no_dispatcher(guard(function()
                  assert.is_nil('should not happen')
              end))
            some_state = peer:state(
              {
                path = path,
                value = value
              },
              {
                success = guard(
                  function()
                    timer:stop(loop)
                    assert.is_true(true)
                    done()
                  end)
            })
            timer = ev.Timer.new(
              guard(
                function()
                  assert.is_true(false)
                  done()
              end),0.1)
            timer:start(loop)
          end)
        
        it(
          'can not add same state again',
          function()
            peer:on_no_dispatcher(guard(function()
                  assert.is_nil('should not happen')
              end))
            assert.has_error(
              function()
                some_state = peer:state
                {
                  path = path,
                  value = value
                }
              end)
          end)
        
        it(
          'can fetch and unfetch states',
          async,
          function(done)
            local timer
            peer:on_no_dispatcher(guard(function()
                  assert.is_nil('should not happen, unfetch broken')
              end))
            peer:fetch(
              path,
              guard(
                function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  if fevent == 'add' then
                    assert.is_equal(fpath,path)
                    assert.is_equal(fdata.value,value)
                    fetcher:unfetch({
                        error = guard(function()
                            assert.is_nil('should not happen')
                          end),
                        success = guard(function()
                            ev.Timer.new(function()
                                done()
                              end,0.1):start(loop)
                            some_state:value(123)
                          end)
                    })
                  else
                    assert.is_nil('fetch callback should not be called more than once')
                  end
              end))
            timer = ev.Timer.new(
              guard(
                function()
                  assert.is_true(false)
                  done()
              end),0.1)
            timer:start(loop)
          end)
      end)
  end)

