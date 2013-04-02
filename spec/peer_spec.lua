package.path = package.path..'../src'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT')

local dt = 0.01

setloop('ev')

describe(
  'A peer',
  function()
    local d
    local peer
    before(function()
        d = jetdaemon.new{port = port}
        d:start()
      end)
    
    after(function()
        d:stop()
      end)
    
    it('provides the correct interface',function()
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
    
    it('on_connect gets called',async,function(done)
        local timer
        local peer
        peer = jetpeer.new
        {
          port = port,
          on_connect = guard(function(p)
              assert.is_equal(peer,p)
              timer:stop(loop)
              peer:close()
              done()
            end)
        }
        timer = ev.Timer.new(guard(function()
              peer:close()
              assert.is_true(false)
          end),dt)
        timer:start(loop)
      end)
    
    describe('when connected',function()
        local peer
        
        local test_a_path = 'test'
        local test_a_value = 1234
        local test_a_state
        
        local test_b_path = 'foo'
        local test_b_value = 'bar'
        local test_b_state
        
        before(async,function(done)
            peer = jetpeer.new
            {
              port = port,
              on_connect = done
            }
          end)
        
        after(function()
            peer:close()
          end)
        
        it('can add a state',async,function(done)
            local timer
            test_a_state = peer:state(
              {
                path = test_a_path,
                value = test_a_value
              },
              {
                success = guard(function()
                    timer:stop(loop)
                    assert.is_true(true)
                    done()
                  end)
            })
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can not add same state again',function()
            assert.has_error(function()
                peer:state
                {
                  path = test_a_path,
                  value = test_a_value
                }
              end)
          end)
        
        it('can add some other state',async,function(done)
            local timer
            test_b_state = peer:state(
              {
                path = test_b_path,
                value = test_b_value
              },
              {
                success = guard(function()
                    timer:stop(loop)
                    assert.is_true(true)
                    done()
                  end)
            })
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can fetch states with simple match string',async,function(done)
            local timer
            peer:fetch(
              test_a_path,
              guard(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  assert.is_equal(fpath,test_a_path)
                  assert.is_equal(fdata.value,test_a_value)
                  fetcher:unfetch()
                  done()
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can fetch states with match array',async,function(done)
            local timer
            peer:fetch(
              {match={test_a_path}},
              guard(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  assert.is_equal(fpath,test_a_path)
                  assert.is_equal(fdata.value,test_a_value)
                  fetcher:unfetch()
                  done()
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('does not fetch on simple path mismatch',async,function(done)
            local timer
            peer:fetch(
              'bla',
              guard(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  fetcher:unfetch()
                  assert.is_true(false)
                  done()
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(true)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('does not fetch on match array mismatch',async,function(done)
            local timer
            peer:fetch(
              {match={'bla'}},
              guard(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  fetcher:unfetch()
                  assert.is_true(false)
                  done()
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(true)
                  done()
              end),dt)
            timer:start(loop)
          end)

        it('can fetch states with match array and a certain value',async,function(done)
            local timer
            peer:fetch(
              {equals=test_a_value},
              guard(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  assert.is_equal(fpath,test_a_path)
                  assert.is_equal(fdata.value,test_a_value)
                  fetcher:unfetch()
                  done()
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
      end)
    
  end)

