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
    setup(
      function()
        d = jetdaemon.new{port = port}
        d:start()
      end)
    
    teardown(
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
      function(done)
        local peer
        peer = jetpeer.new
        {
          port = port,
          on_connect = async(
            function(p)
              assert.is_equal(peer,p)
              done()
            end)
        }
        finally(function() peer:close() end)
      end)
    
    describe(
      'when connected',
      function()
        local peer
        local path = 'test'
        local value = 1234
        setup(
          function(done)
            peer = jetpeer.new
            {
              port = port,
              on_connect = async(
                function(p)
                  done()
                end)
            }
          end)
        
        teardown(
          function()
            peer:close()
          end)
        
        local some_state
        
        it(
          'can add states',
          function(done)
            peer:on_no_dispatcher(async(function()
                  assert.is_nil('should not happen')
              end))
            some_state = peer:state(
              {
                path = path,
                value = value
              },
              {
                success = async(
                  function()
                    assert.is_true(true)
                    done()
                  end)
            })
          end)
        
        it(
          'can not add same state again',
          function()
            assert.has_error(function()
                peer:state({
                    path = path,
                    value = value
                })
              end)
          end)
        
        it(
          'can fetch and unfetch states',
          function(done)
            peer:on_no_dispatcher(async(function()
                  assert.is_nil('should not happen, unfetch broken')
              end))
            peer:fetch(
              path,
              async(
                function(fpath,fevent,fdata,fetcher)
                  if fevent == 'add' then
                    assert.is_equal(fpath,path)
                    assert.is_equal(fdata.value,value)
                    fetcher:unfetch({
                        error = async(function()
                            assert.is_nil('should not happen')
                          end),
                        success = async(function()
                            some_state:value(123)
                            done()
                          end)
                    })
                  else
                    assert.is_nil('fetch callback should not be called more than once')
                  end
              end))
          end)
      end)
  end)

