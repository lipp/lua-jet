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
    
    describe('when connected working with test_a and test_b',function()
        local peer
        
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
        
        local test_a = {
          path = 'test',
          value = 1234
        }
        
        local test_b = {
          path = 'foo',
          value = 'bar'
        }
        
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
                                  peer:on_no_dispatcher(function() end)
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
                      error = async(function(err)
                          assert.is_falsy(err)
                        end)
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
        
        it('can fetch states with limited number updating content',function(done)
            local count = 0
            local newval = 99990
            local a_val = test_a.state:value()
            local b_val = test_b.state:value()
            test_b.state:value(a_val)
            local expected = {
              {
                event = 'add',
                value = a_val,
                action = function()
                  test_a.state:value(191)
                end
              },
              {
                event = 'remove',
                value = 191,
                action = function()
                  test_b.state:value(a_val)
                end
              },
              {
                event = 'add',
                value = a_val,
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
        
        it('can fetch case insensitive',function(done)
            local expected = {
              ['a/TEST'] = 879,
              ['a/TEST/sub'] = 333,
              ['test'] = 879,
            }
            for path in pairs(expected) do
              done:wait_unordered(path)
            end
            local fetcher = peer:fetch({
                match = {'test'},
                caseInsensitive = true
              },async(function(fpath,fevent,fvalue,fetcher)
                  assert.is_equal(fevent,'add')
                  assert.is_equal(expected[fpath],fvalue)
                  done(fpath)
              end))
          end)
        
        
      end)
    
    describe('when working with clean jet',function()
        local peer
        
        before_each(function(done)
            peer = jetpeer.new
            {
              port = port,
              on_connect = async(function() done() end)
            }
          end)
        
        after_each(function()
            peer:close()
          end)
        
        it('fetch with sort works when states are already added',function(done)
            local expected_adds = {
              [1] = {
                path = 'abc',
                value = 'bla',
                index = 1
              },
              [2] = {
                path = 'cde',
                value = 123,
                index = 2
              }
            }
            
            -- add some other states which are not expected
            peer:state{
              path = 'xcd',
              value = true
            }
            
            peer:state{
              path = 'ii98',
              value = {}
            }
            
            -- add expected states in reverse order to be more evil
            for i=#expected_adds,1,-1 do
              peer:state{
                path = expected_adds[i].path,
                value = expected_adds[i].value
              }
            end
            
            
            local count = 0
            local fetcher = peer:fetch({
                sort = {
                  from = 1,
                  to = 2
                }
              },async(function(path,event,data,index)
                  count = count + 1
                  if event == 'add' then
                    local expected = expected_adds[count]
                    assert.is_same(path,expected.path)
                    assert.is_same(data,expected.value)
                    assert.is_same(index,expected.index)
                  else
                    assert.is_nil('should not happen')
                  end
                  if count == #expected_adds then
                    done()
                  end
              end))
            
            finally(function() fetcher:unfetch() end)
            
            
          end)
        
        it('fetch with sort works when states are added afterwards',function(done)
            local expected = {
              -- when xcd is added
              {
                path = 'xcd',
                value = true,
                index = 1,
                event = 'add'
              },
              -- when ii98 is added, xcd is reordered
              {
                path = 'xcd',
                value = true,
                index = 2,
                event = 'change'
              },
              {
                path = 'ii98',
                value = {},
                index = 1,
                event = 'add'
              },
              -- when abc is added, ii98 is reordered and xcd  is
              -- removed
              {
                path = 'xcd',
                value = true,
                index = 2,
                event = 'remove'
              },
              {
                path = 'ii98',
                value = {},
                index = 2,
                event = 'change'
              },
              {
                path = 'abc',
                value = 123,
                index = 1,
                event = 'add'
              },
            }
            
            
            local count = 0
            local fetcher = peer:fetch({
                sort = {
                  from = 1,
                  to = 2
                }
              },async(function(path,event,data,index)
                  count = count + 1
                  local fetched = {
                    path = path,
                    event = event,
                    value = data,
                    index = index
                  }
                  assert.is_same(fetched,expected[count])
                  if count == #expected then
                    done()
                  end
              end))
            
            finally(function() fetcher:unfetch() end)
            
            -- add some other states which are not expected
            peer:state{
              path = 'xcd',
              value = true
            }
            
            peer:state{
              path = 'ii98',
              value = {}
            }
            
            peer:state{
              path = 'abc',
              value = 123
            }
            
            
          end)
        
      end)
    
  end)
