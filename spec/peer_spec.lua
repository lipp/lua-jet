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
        
        local test_a = {
          path = 'test',
          value = 1234
        }
        
        local test_b = {
          path = 'foo',
          value = 'bar'
        }
        
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
            test_a.state = peer:state(
              {
                path = test_a.path,
                value = test_a.value,
                set = function(newval)
                  test_a.value = newval
                end
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
                  path = test_a.path,
                  value = test_a.value
                }
              end)
          end)
        
        it('can add some other state',async,function(done)
            local timer
            test_b.state = peer:state(
              {
                path = test_b.path,
                value = test_b.value
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
        
        it('another peer can set value and change notifications flow around',async,function(done)
            local new_val = 716
            local other = jetpeer.new
            {
              port = port,
              on_connect = guard(function(other)
                  other:fetch(test_a.path,guard(function(path,event,value,fetcher)
                        if event == 'change' then
                          assert.is_equal(value,new_val)
                          fetcher:unfetch()
                          done()
                        end
                    end))
                  
                  other:set(test_a.path,new_val,{
                      success = guard(function()
                          assert.is_true(true)
                        end),
                      error = function(err)
                        assert.is_falsy(err)
                      end
                  })
                end)
            }
          end)
        
        
        it('can fetch states with simple match string',async,function(done)
            local timer
            peer:fetch(
              test_a.path,
              guard(function(fpath,fevent,fvalue,fetcher)
                  timer:stop(loop)
                  assert.is_equal(fpath,test_a.path)
                  assert.is_equal(fvalue,test_a.state:value())
                  fetcher:unfetch()
                  done()
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can remove a state',async,function(done)
            local timer
            peer:fetch(
              test_a.path,
              guard(function(fpath,fevent,fvalue,fetcher)
                  if fevent == 'remove' then
                    timer:stop(loop)
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    fetcher:unfetch()
                    done()
                  end
              end))
            test_a.state:remove()
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can (re)add a state',async,function(done)
            local timer
            peer:fetch(
              test_a.path,
              guard(function(fpath,fevent,fvalue,fetcher)
                  timer:stop(loop)
                  assert.is_equal(fpath,test_a.path)
                  assert.is_equal(fvalue,test_a.state:value())
                  fetcher:unfetch()
                  done()
              end))
            test_a.state:add()
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can fetch states with match array',async,function(done)
            local timer
            peer:fetch(
              {match={test_a.path}},
              guard(function(fpath,fevent,fvalue,fetcher)
                  timer:stop(loop)
                  assert.is_equal(fpath,test_a.path)
                  assert.is_equal(fvalue,test_a.state:value())
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
            local added
            local changed
            local readded
            local other_value = 333
            peer:fetch(
              {equals=test_a.value},
              guard(function(fpath,fevent,fvalue,fetcher)
                  if not added then
                    added = true
                    assert.is_equal(fevent,'add')
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    test_a.state:value(other_value)
                  elseif not changed then
                    changed = true
                    assert.is_equal(fevent,'remove')
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,other_value)
                    test_a.state:value(test_a.value)
                  else
                    assert.is_equal(fevent,'add')
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    timer:stop(loop)
                    fetcher:unfetch()
                    done()
                  end
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can fetch with deps',async,function(done)
            local timer
            peer:fetch({
                match = {'test'},
                deps = {
                  {
                    path = 'foo',
                    equals = 'bar'
                  }
                }
              },guard(function(fpath,fevent,fvalue,fetcher)
                  if fevent == 'add' then
                    test_a.state:value(879)
                  elseif fevent == 'change' then
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    assert.is_equal(fvalue,879)
                    test_b.state:value('hello')
                  elseif fevent == 'remove' then
                    timer:stop(loop)
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    fetcher:unfetch()
                    done()
                  end
              end))
            timer = ev.Timer.new(guard(function()
                  assert.is_true(false)
                  done()
              end),dt*3)
            timer:start(loop)
            
          end)
        
      end)
    
  end)

