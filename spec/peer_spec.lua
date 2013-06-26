package.path = package.path..'../src'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT')

local dt = 0.05

setloop('ev')

describe(
  'A peer',
  function()
    local d
    local peer
    setup(function()
        d = jetdaemon.new{port = port}
        d:start()
      end)
    
    teardown(function()
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
    
    it('on_connect gets called',function(done)
        local peer
        peer = jetpeer.new
        {
          port = port,
          on_connect = async(function(p)
              assert.is_equal(peer,p)
              done()
            end)
        }
        finally(function() peer:close() end)
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
        
        setup(function(done)
            peer = jetpeer.new
            {
              port = port,
              on_connect = async(function() done() end)
            }
          end)
        
        teardown(function()
            peer:close()
          end)
        
        it('can add a state',function(done)
            test_a.state = peer:state(
              {
                path = test_a.path,
                value = test_a.value,
                set = function(newval)
                  test_a.value = newval
                end
              },
              {
                success = async(function()
                    assert.is_true(true)
                    done()
                  end)
            })
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
        
        it('can add some other state',function(done)
            test_b.state = peer:state(
              {
                path = test_b.path,
                value = test_b.value
              },
              {
                success = async(function()
                    assert.is_true(true)
                    done()
                  end),
                error = async(function()
                    assert.is_nil('should not happen')
                  end)
            })
          end)
        
        it(
          'can fetch and unfetch states',
          function(done)
            peer:on_no_dispatcher(async(function()
                  assert.is_nil('should not happen, unfetch broken')
              end))
            peer:fetch(
              test_a.path,
              async(
                function(fpath,fevent,fvalue,fetcher)
                  if fevent == 'add' then
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    fetcher:unfetch({
                        error = async(function()
                            assert.is_nil('should not happen')
                          end),
                        success = async(function()
                            -- change value and wait some time
                            ev.Timer.new(async(function()
                                  done()
                              end),0.1):start(loop)
                            test_a.state:value(123)
                          end)
                    })
                  else
                    assert.is_nil('fetch callback should not be called more than once')
                  end
              end))
          end)
        
        it('another peer can set value and change notifications are send',function(done)
            local new_val = 716
            local other = jetpeer.new
            {
              port = port,
              on_connect = async(function(other)
                  other:fetch(test_a.path,async(function(path,event,value,fetcher)
                        if event == 'change' then
                          assert.is_equal(value,new_val)
                          fetcher:unfetch()
                          done()
                        end
                    end))
                  
                  other:set(test_a.path,new_val,{
                      success = async(function()
                          assert.is_true(true)
                        end),
                      error = function(err)
                        assert.is_falsy(err)
                      end
                  })
                end)
            }
          end)
        
        
        it('can fetch states with simple match string',function(done)
            local fetcher = peer:fetch(
              test_a.path,
              async(function(fpath,fevent,fvalue)
                  assert.is_equal(fpath,test_a.path)
                  assert.is_equal(fvalue,test_a.state:value())
                  done()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can remove a state',function(done)
            local fetcher = peer:fetch(
              test_a.path,
              async(function(fpath,fevent,fvalue)
                  if fevent == 'remove' then
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    done()
                  end
              end))
            finally(function() fetcher:unfetch() end)
            test_a.state:remove()
          end)
        
        it('can (re)add a state',function(done)
            local fetcher = peer:fetch(
              test_a.path,
              async(function(fpath,fevent,fvalue,fetcher)
                  assert.is_equal(fpath,test_a.path)
                  assert.is_equal(fvalue,test_a.state:value())
                  done()
              end))
            finally(function() fetcher:unfetch() end)
            test_a.state:add()
          end)
        
        it('can fetch states with match array',function(done)
            local fetcher = peer:fetch(
              {match={test_a.path}},
              async(function(fpath,fevent,fvalue,fetcher)
                  assert.is_equal(fpath,test_a.path)
                  assert.is_equal(fvalue,test_a.state:value())
                  done()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('does not fetch on simple path mismatch',function(done)
            local timer
            local fetcher = peer:fetch(
              'bla',
              async(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  fetcher:unfetch()
                  assert.is_falsy('should not happen')
                  done()
              end))
            timer = ev.Timer.new(async(function()
                  assert.is_true(true)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('does not fetch on match array mismatch',function(done)
            local timer
            peer:fetch(
              {match={'bla'}},
              async(function(fpath,fevent,fdata,fetcher)
                  timer:stop(loop)
                  fetcher:unfetch()
                  assert.is_falsy('should not happen')
                  done()
              end))
            timer = ev.Timer.new(async(function()
                  assert.is_true(true)
                  done()
              end),dt)
            timer:start(loop)
          end)
        
        it('can fetch states with match array and a certain value',function(done)
            local added
            local changed
            local readded
            local other_value = 333
            local fetcher = peer:fetch(
              {equals=test_a.value},
              async(function(fpath,fevent,fvalue)
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
                    done()
                  end
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch states with limited number',function(done)
            local count = 0
            local fetcher = peer:fetch(
              {
                max = 1
              },
              async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal(fevent,'add')
              end))
            finally(function() fetcher:unfetch() end)
            ev.Timer.new(
              async(function()
                  assert.is_equal(count,1)
                  done()
              end),0.01):start(loop)
          end)
        
        it('can fetch states with limited number updating content',function(done)
            local count = 0
            local newval = 99990
            local a_val = test_a.state:value()
            local b_val = test_b.state:value()
            local expected = {
              {
                event = 'add',
                value = a_val,
                path = test_a.path,
                action = function()
                  test_a.state:value(newval)
                end
              },
              {
                event = 'remove',
                value = newval,
                path = test_a.path,
                action = function()
                  test_b.state:value(a_val)
                end
              },
              {
                event = 'add',
                value = a_val,
                path = test_b.path,
              }
            }
            local fetcher = peer:fetch(
              {
                max = 1,
                equals = a_val
              },
              async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal(fevent,expected[count].event)
                  assert.is_equal(fvalue,expected[count].value)
                  if expected[count].action then
                    expected[count].action()
                  end
                  if count == #expected then
                    done()
                  end
              end))
            finally(function()
                fetcher:unfetch()
                test_a.state:value(a_val)
                test_b.state:value(b_val)
              end)
          end)
        
        
        
        it('can fetch with deps',function(done)
            local fetcher = peer:fetch({
                match = {'test'},
                deps = {
                  {
                    path = 'foo',
                    equals = 'bar'
                  }
                }
              },async(function(fpath,fevent,fvalue)
                  if fevent == 'add' then
                    test_a.state:value(879)
                  elseif fevent == 'change' then
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    assert.is_equal(fvalue,879)
                    test_b.state:value('hello')
                  elseif fevent == 'remove' then
                    assert.is_equal(fpath,test_a.path)
                    assert.is_equal(fvalue,test_a.state:value())
                    done()
                  end
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch with deps with backrefs',function(done)
            local state_a
            local state_a_sub
            local fetcher = peer:fetch({
                match = {'a/([^/]*)$'},
                deps = {
                  {
                    path = 'a/\\1/sub',
                    equals = 123
                  }
                }
              },async(function(fpath,fevent,fvalue,fetcher)
                  if fevent == 'add' then
                    assert.is_equal(fpath,'a/TEST')
                    assert.is_equal(fvalue,3)
                    state_a:value(879)
                  elseif fevent == 'change' then
                    assert.is_equal(fpath,'a/TEST')
                    assert.is_equal(fvalue,879)
                    state_a_sub:value(333)
                  elseif fevent == 'remove' then
                    assert.is_equal(fpath,'a/TEST')
                    assert.is_equal(fvalue,879)
                    done()
                  end
              end))
            finally(function() fetcher:unfetch() end)
            state_a = peer:state
            {
              path = 'a/TEST',
              value = 3
            }
            state_a_sub = peer:state
            {
              path = 'a/TEST/sub',
              value = 123
            }
            
          end)
        
      end)
    
  end)

