local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT') or 11122+5

local dt = 0.05

setloop('ev')

describe(
  'A peer basic tests',
  function()
    local daemon
    local peer
    setup(function()
        daemon = jetdaemon.new{
          port = port,
          print = function() end
        }
        daemon:start()
      end)
    
    teardown(function()
        daemon:stop()
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
        peer = jetpeer.new
        {
          port = port,
          on_connect = async(function(p)
              assert.is_equal(peer,p)
              done()
            end)
        }
        --        finally(function() peer:close() end)
      end)
    
    it('can add a state',function(done)
        peer:state(
          {
            path = 'bla',
            value = 213
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
              path = 'bla',
              value = 623
            }
          end)
      end)
    
    it('can add some other state',function(done)
        peer:state(
          {
            path = 'blub',
            value = 33333
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
        finally(function()
            peer:close()
          end)
      end)
    
    describe('with some states in place',function()
        local peer
        local states = {}
        
        before_each(function(done)
            peer = jetpeer.new
            {
              port = port,
              on_connect = async(function()
                  states.test = peer:state
                  {
                    path = 'test',
                    value = 1234,
                    set = function() end -- make state writeable
                  }
                  states.foo = peer:state
                  {
                    path = 'foo',
                    value = 'bar'
                  }
                  states.peter = peer:state
                  {
                    path = 'persons/1',
                    value = {
                      name = 'peter',
                      age = 35
                    }
                  }
                  states.peters_hobby = peer:state
                  {
                    path = 'persons/1/hobby',
                    value = 'tennis'
                  }
                  states.ben = peer:state
                  {
                    path = 'persons/2',
                    value = {
                      name = 'ben',
                      age = 46
                    }
                  }
                  states.bens_hobby = peer:state({
                      path = 'persons/2/hobby',
                      value = 'soccer'
                      },{
                      success = function()
                        done()
                      end
                  })
                end)
            }
          end)
        
        after_each(function(done)
            peer:close()
          end)
        
        it(
          'can fetch and unfetch states',
          function(done)
            peer:on_no_dispatcher(async(function()
                  assert.is_nil('should not happen, unfetch broken')
              end))
            peer:fetch(
              '^test$',
              async(
                function(fpath,fevent,fvalue,fetcher)
                  if fevent == 'add' then
                    assert.is_equal(fpath,states.test:path())
                    assert.is_equal(fvalue,states.test:value())
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
                            states.test:value(123)
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
                  other:fetch(states.test:path(),async(function(path,event,value,fetcher)
                        if event == 'change' then
                          assert.is_equal(value,new_val)
                          fetcher:unfetch()
                          done()
                        end
                    end))
                  
                  other:set(states.test:path(),new_val,{
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
              states.test:path(),
              async(function(fpath,fevent,fvalue)
                  assert.is_equal(fpath,states.test:path())
                  assert.is_equal(fvalue,states.test:value())
                  done()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can remove a state',function(done)
            local fetcher = peer:fetch(
              states.test:path(),
              async(function(fpath,fevent,fvalue)
                  if fevent == 'remove' then
                    assert.is_equal(fpath,states.test:path())
                    assert.is_equal(fvalue,states.test:value())
                    done()
                  end
              end))
            finally(function() fetcher:unfetch() end)
            states.test:remove()
          end)
        
        it('can (re)add a state',function(done)
            local expected = {
              {
                event = 'add',
                action = function()
                  states.test:remove()
                end,
              },
              {
                event = 'remove',
                action = function()
                  states.test:add()
                end
              },
              {
                event = 'add',
                action = function()
                  done()
                end
              }
            }
            local count = 0
            local fetcher = peer:fetch(
              states.test:path(),
              async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal(expected[count].event,fevent)
                  assert.is_equal(fpath,states.test:path())
                  expected[count].action()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch states with match array',function(done)
            local fetcher = peer:fetch(
              {match={states.test:path()}},
              async(function(fpath,fevent,fvalue)
                  assert.is_equal(fpath,states.test:path())
                  assert.is_equal(fvalue,states.test:value())
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
                  assert.is_falsy('should not happen'..fpath)
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
        
        it('can fetch states with "equals" and no "prop" value',function(done)
            local oldval = states.test:value()
            local newval = 333
            local expected = {
              {
                event = 'add',
                value = oldval,
                action = function()
                  states.test:value(newval)
                end
              },
              {
                event = 'remove',
                value = newval,
                action = function()
                  states.test:value(oldval)
                end
              },
              {
                event = 'add',
                value = oldval,
                action = function()
                  done()
                end
              },
            }
            local count = 0
            local fetcher = peer:fetch(
              {where={op='equals',value=states.test:value()}},
              async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal(expected[count].event,fevent)
                  assert.is_equal(expected[count].value,fvalue)
                  expected[count].action()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch states with "equalsNot" and no "prop" value',function(done)
            local oldval = states.bens_hobby:value()
            local newval = states.peters_hobby:value()
            local expected = {
              {
                event = 'add',
                value = oldval,
                action = function()
                  states.bens_hobby:value(newval)
                end
              },
              {
                event = 'remove',
                value = newval,
                action = function()
                  states.bens_hobby:value(oldval)
                end
              },
              {
                event = 'add',
                value = oldval,
                action = function()
                  done()
                end
              },
            }
            local count = 0
            local fetcher = peer:fetch(
              {
                match = {'hobby'},
                where = {
                  op = 'equalsNot',
                  value = states.peters_hobby:value()
                }
              },
              async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal('persons/2/hobby',fpath)
                  assert.is_equal(expected[count].event,fevent)
                  assert.is_equal(expected[count].value,fvalue)
                  expected[count].action()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch states with "equalsNot" and no "prop" value',function(done)
            local oldval = states.peter:value()
            local newval = {
              age = 40,
              name = 'peter'
            }
            local expected = {
              {
                event = 'add',
                value = oldval,
                action = function()
                  states.peter:value(newval)
                end
              },
              {
                event = 'remove',
                value = newval,
                action = function()
                  states.peter:value(oldval)
                end
              },
              {
                event = 'add',
                value = oldval,
                action = function()
                  done()
                end
              },
            }
            local count = 0
            local fetcher = peer:fetch(
              {
                match = {'persons/.*'},
                where = {
                  prop = 'age',
                  op = 'lessThan',
                  value = 40,
                }
              },
              async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal('persons/1',fpath)
                  assert.is_equal(expected[count].event,fevent)
                  assert.is_same(expected[count].value,fvalue)
                  expected[count].action()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch states with "equals" and "prop" path',function(done)
            local fetcher = peer:fetch(
              {where={op='equals',value='peter',prop='name'}},
              async(function(fpath,fevent,fvalue,fetcher)
                  assert.is_equal(fevent,'add')
                  assert.is_equal(fpath,states.peter:path())
                  assert.is_same(fvalue,states.peter:value())
                  done()
              end))
            
            finally(function()
                fetcher:unfetch()
              end)
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
            local test_val = states.test:value()
            local foo_val = states.foo:value()
            local expected = {
              {
                event = 'add',
                value = test_val,
                path = states.test:path(),
                action = function()
                  states.test:value(newval)
                end
              },
              {
                event = 'remove',
                value = newval,
                path = states.test:path(),
                action = function()
                  states.foo:value(test_val)
                end
              },
              {
                event = 'add',
                value = test_val,
                path = states.foo:path(),
                action = function()
                  ev.Timer.new(function()
                      done()
                    end,0.001):start(loop)
                end
              }
            }
            local fetcher = peer:fetch(
              {
                max = 1,
                where={op='equals',value=test_val},
              },
              async(function(fpath,fevent,fvalue,fetcher)
                  count = count + 1
                  assert.is_equal(fevent,expected[count].event)
                  assert.is_equal(fvalue,expected[count].value)
                  expected[count].action()
              end))
            finally(function()
                fetcher:unfetch()
              end)
          end)
        
        it('can fetch with deps',function(done)
            local newval = 7678
            local expected = {
              {
                event = 'add',
                path = states.test:path(),
                value = states.test:value(),
                action = function()
                  states.test:value(newval)
                end
              },
              {
                event = 'change',
                path = states.test:path(),
                value = newval,
                action = function()
                  states.foo:value(999)
                end
              },
              {
                event = 'remove',
                path = states.test:path(),
                value = newval,
                action = function()
                  done()
                end
              }
            }
            local count = 0
            local fp = {
              match = {states.test:path()},
              deps = {
                {
                  path = states.foo:path(),
                  where={op='equals',value=states.foo:value()},
                }
              }
            }
            local fetcher = peer:fetch({
                match = {states.test:path()},
                deps = {
                  {
                    path = states.foo:path(),
                    where={op='equals',value=states.foo:value()},
                  }
                }
              },async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal(fpath,expected[count].path)
                  assert.is_equal(fevent,expected[count].event)
                  assert.is_equal(fvalue,expected[count].value)
                  expected[count].action()
              end))
            finally(function() fetcher:unfetch() end)
          end)
        
        it('can fetch with deps with backrefs',function(done)
            local newval = 66
            local expected = {
              {
                event = 'add',
                value = states.peter:value(),
                action = function()
                  states.peter:value(newval)
                end
              },
              {
                event = 'change',
                value = newval,
                action = function()
                  states.peters_hobby:value('fishing')
                end
              },
              {
                event = 'remove',
                value = newval,
                action = function()
                  done()
                end
              },
            }
            local count = 0
            local fetcher = peer:fetch({
                match = {'persons/([^/]*)$'},
                deps = {
                  {
                    path = 'persons/\\1/hobby',
                    where = {
                      op = 'equals',
                      value = 'tennis'
                    }
                  }
                }
              },async(function(fpath,fevent,fvalue,fetcher)
                  count = count + 1
                  assert.is_equal(fpath,states.peter:path())
                  assert.is_same(fvalue,expected[count].value)
                  assert.is_equal(fevent,expected[count].event)
                  expected[count].action()
              end))
            finally(function() fetcher:unfetch() end)
            
          end)
        
        it('can fetch case insensitive',function(done)
            local expected = {
              {
                path = 'persons/1/hobby',
                value = 'tennis',
                event = 'add',
                action = function()
                  states.peters_hobby:value('socker')
                end
              },
              {
                path = 'persons/1/hobby',
                value = 'socker',
                event = 'change',
                action = function()
                  done()
                end
              },
            }
            local count = 0
            local fetcher = peer:fetch({
                match = {'persons/1/HOBBY'},
                caseInsensitive = true,
              },async(function(fpath,fevent,fvalue)
                  count = count + 1
                  assert.is_equal(fevent,expected[count].event)
                  assert.is_equal(fpath,expected[count].path)
                  assert.is_equal(fvalue,expected[count].value)
                  expected[count].action()
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
        
        it('set gets timeout error',function(done)
            local not_responding = peer:state
            {
              path = 'abc',
              value = 123,
              set_async = async(function() -- never responds
                end)
            }
            
            peer:set('abc',231,{
                timeout = 0.2,
                success = async(function()
                    assert.is_nil('should never happen')
                  end),
                error = async(function(err)
                    assert.is_equal(err.message,'Response Timeout')
                    assert.is_equal(err.code,-32001)
                    done()
                  end)
            })
          end)
        
        it('call gets timeout error',function(done)
            local not_responding = peer:method
            {
              path = 'abc2',
              call_async = async(function() -- never responds
                end)
            }
            
            peer:call('abc2',{},{
                timeout = 0.2,
                success = async(function()
                    assert.is_nil('should never happen')
                  end),
                error = async(function(err)
                    assert.is_equal(err.message,'Response Timeout')
                    assert.is_equal(err.code,-32001)
                    done()
                  end)
            })
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
              },
              [3] = {
                path = 'iii',
                value = {bla=123},
                index = 3
              }
            }
            
            -- add some other states which are not expected
            peer:state{
              path = 'xyz',
              value = {foo = 'bar'}
            }
            
            -- add expected states in reverse order to be more evil
            for i=#expected_adds,1,-1 do
              peer:state{
                path = expected_adds[i].path,
                value = expected_adds[i].value
              }
            end
            
            local fetcher
            fetcher = peer:fetch({
                sort = {
                  from = 1,
                  to = #expected_adds
                }
              },async(function(sorted,n,fetcher2)
                  assert.is_equal(n,#expected_adds)
                  assert.is_equal(fetcher,fetcher2)
                  assert.is_same(sorted,expected_adds)
                  done()
              end))
            
            finally(function() fetcher:unfetch() end)
            
            
          end)
        
        it('fetch with sort has n properly reduced',function(done)
            local a = peer:state{path = 'a', value = 1}
            local b = peer:state{path = 'b', value = 2}
            local c = peer:state{path = 'c', value = 3}
            local d = peer:state{path = 'd', value = 4}
            local e = peer:state{path = 'e', value = 5}
            
            local expected = {
              {
                sorted = {
                  {path = 'a', value = 1, index = 1},
                  {path = 'b', value = 2, index = 2},
                  {path = 'c', value = 3, index = 3},
                  {path = 'd', value = 4, index = 4},
                },
                n = 4,
                action = function()
                  c:remove()
                end
              },
              {
                sorted = {
                  {path = 'd', value = 4, index = 3},
                  {path = 'e', value = 5, index = 4},
                },
                n = 4,
                action = function()
                  e:remove()
                end
              },
              {
                sorted = {
                },
                n = 3,
                action = function()
                  e:add()
                end
              },
              {
                sorted = {
                  {path = 'e', value = 5, index = 4},
                },
                n = 4,
                action = function()
                  d:remove()
                end
              },
              {
                sorted = {
                  {path = 'e', value = 5, index = 3},
                },
                n = 3,
                action = function()
                  done()
                end
              },
            }
            
            
            local count = 0
            
            local fetcher = peer:fetch({
                sort = {
                  from = 1,
                  to = 4
                }
              },async(function(sorted,n)
                  count = count + 1
                  assert.is_equal(expected[count].n,n)
                  assert.is_same(expected[count].sorted,sorted)
                  assert.is_same(#expected[count].sorted,#sorted)
                  expected[count].action()
              end))
            
            finally(function() fetcher:unfetch() end)
            
            
          end)
        
        it('fetch with sort has n properly reduced with from = 2',function(done)
            local a = peer:state{path = 'a', value = 1}
            local b = peer:state{path = 'b', value = 2}
            local c = peer:state{path = 'c', value = 3}
            local d = peer:state{path = 'd', value = 4}
            local e = peer:state{path = 'e', value = 5}
            
            local expected = {
              {
                sorted = {
                  {path = 'b', value = 2, index = 2},
                  {path = 'c', value = 3, index = 3},
                  {path = 'd', value = 4, index = 4},
                },
                n = 3,
                action = function()
                  c:remove()
                end
              },
              {
                sorted = {
                  {path = 'd', value = 4, index = 3},
                  {path = 'e', value = 5, index = 4},
                },
                n = 3,
                action = function()
                  e:remove()
                end
              },
              {
                sorted = {
                },
                n = 2,
                action = function()
                  e:add()
                end
              },
              {
                sorted = {
                  {path = 'e', value = 5, index = 4},
                },
                n = 3,
                action = function()
                  d:remove()
                end
              },
              {
                sorted = {
                  {path = 'e', value = 5, index = 3},
                },
                n = 2,
                action = function()
                  b:remove()
                end
              },
              {
                sorted = {
                  {path = 'e', value = 5, index = 2},
                },
                n = 1,
                action = function()
                  e:remove()
                end
              },
              {
                sorted = {
                },
                n = 0,
                action = function()
                  done()
                end
              },
            }
            
            
            local count = 0
            
            local fetcher = peer:fetch({
                sort = {
                  from = 2,
                  to = 4
                }
              },async(function(sorted,n)
                  count = count + 1
                  assert.is_equal(expected[count].n,n)
                  assert.is_same(expected[count].sorted,sorted)
                  assert.is_same(#expected[count].sorted,#sorted)
                  expected[count].action()
              end))
            
            finally(function() fetcher:unfetch() end)
            
            
          end)
        
        it('fetch with from = 2 works when elements from top are removed',function(done)
            local a = peer:state{path = 'a', value = 1}
            local b = peer:state{path = 'b', value = 2}
            local c = peer:state{path = 'c', value = 3}
            local d = peer:state{path = 'd', value = 4}
            local e = peer:state{path = 'e', value = 5}
            
            local expected = {
              {
                sorted = {
                  {path = 'b', value = 2, index = 2},
                  {path = 'c', value = 3, index = 3},
                  {path = 'd', value = 4, index = 4},
                },
                n = 3,
                action = function()
                  a:remove()
                end
              },
              {
                sorted = {
                  {path = 'c', value = 3, index = 2},
                  {path = 'd', value = 4, index = 3},
                  {path = 'e', value = 5, index = 4},
                },
                n = 3,
                action = function()
                  done()
                end
              }
            }
            
            
            local count = 0
            
            local fetcher = peer:fetch({
                sort = {
                  from = 2,
                  to = 4
                }
              },async(function(sorted,n)
                  count = count + 1
                  assert.is_equal(expected[count].n,n)
                  assert.is_same(expected[count].sorted,sorted)
                  assert.is_same(#expected[count].sorted,#sorted)
                  expected[count].action()
              end))
            
            finally(function() fetcher:unfetch() end)
            
            
          end)
        
        it('fetch with sort works when states are added afterwards',function(done)
            local expected = {
              -- when xcd is added
              {
                value = {},
                n = 0
              },
              {
                value = {
                  {
                    path = 'xcd',
                    value = true,
                    index = 1,
                  }
                },
                n = 1
              },
              -- when ii98 is added, xcd is reordered
              {
                n = 2,
                value = {
                  {
                    path = 'ii98',
                    value = {},
                    index = 1,
                  },
                  {
                    path = 'xcd',
                    value = true,
                    index = 2,
                  }
                }
              },
              -- when abc is added, ii98 is reordered and xcd  is
              -- removed
              {
                n = 2,
                value = {
                  {
                    path = 'abc',
                    value = 123,
                    index = 1,
                  },
                  {
                    path = 'ii98',
                    value = {},
                    index = 2,
                  },
                }
              }
            }
            
            
            local count = 0
            local fetcher = peer:fetch({
                sort = {
                  from = 1,
                  to = 2
                }
              },async(function(sorted,n)
                  count = count + 1
                  local s = {
                    value = sorted,
                    n = n
                  }
                  assert.is_same(s,expected[count])
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
    
    describe('when working with clean jet with msgpack encoding',function()
        
        if pcall(require,'cmsgpack') then
          
          it('fetch with sort works when states are already added',function(done)
              local peer = jetpeer.new
              {
                port = port,
                encoding = 'msgpack',
              }
              finally(function()
                  peer:close()
                end)
              
              local expected = {
                -- when xcd is added
                {
                  value = {},
                  n = 0
                },
                {
                  value = {
                    {
                      path = 'xcd',
                      value = true,
                      index = 1,
                    }
                  },
                  n = 1
                },
                -- when ii98 is added, xcd is reordered
                {
                  n = 2,
                  value = {
                    {
                      path = 'ii98',
                      value = {},
                      index = 1,
                    },
                    {
                      path = 'xcd',
                      value = true,
                      index = 2,
                    }
                  }
                },
                -- when abc is added, ii98 is reordered and xcd  is
                -- removed
                {
                  n = 2,
                  value = {
                    {
                      path = 'abc',
                      value = 123,
                      index = 1,
                    },
                    {
                      path = 'ii98',
                      value = {},
                      index = 2,
                    },
                  }
                }
              }
              
              
              local count = 0
              local fetcher = peer:fetch({
                  sort = {
                    from = 1,
                    to = 2
                  }
                },async(function(sorted,n)
                    count = count + 1
                    local s = {
                      value = sorted,
                      n = n
                    }
                    assert.is_same(s,expected[count])
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
        else
          pending('test msgpack')
        end
        
      end)
    
  end)
