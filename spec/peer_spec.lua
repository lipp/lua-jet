package.path = package.path..'../src'

local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT')

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
                      age = 35
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
        
        it('can fetch states with a certain value',function(done)
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
        
        it('can fetch states with a certain object value',function(done)
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
        
        -- it('can fetch case insensitive',function(done)
        --     local expected = {
        --       ['a/TEST'] = 879,
        --       ['a/TEST/sub'] = 333,
        --       ['test'] = 879,
        --     }
        --     for path in pairs(expected) do
        --       done:wait_unordered(path)
        --     end
        --     local fetcher = peer:fetch({
        --                                   match = {'test'},
        --         caseInsensitive = true,
        --       },async(function(fpath,fevent,fvalue)
        --                  print(fpath,fevent,fvalue)
        --           assert.is_equal(fevent,'add')
        --           assert.is_equal(expected[fpath],fvalue)
        --           done(fpath)
        --       end))
        --   end)
        
        
        --   end)
        
        -- describe('when working with clean jet',function()
        --     local peer
        
        --     before_each(function(done)
        --         peer = jetpeer.new
        --         {
        --           port = port,
        --           on_connect = async(function() done() end)
        --         }
        --       end)
        
        --     after_each(function()
        --         peer:close()
        --       end)
        
        --     it('fetch with sort works when states are already added',function(done)
        --         local expected_adds = {
        --           [1] = {
        --             path = 'abc',
        --             value = 'bla',
        --             index = 1
        --           },
        --           [2] = {
        --             path = 'cde',
        --             value = 123,
        --             index = 2
        --           }
        --         }
        
        --         -- add some other states which are not expected
        --         peer:state{
        --           path = 'xcd',
        --           value = true
        --         }
        
        --         peer:state{
        --           path = 'ii98',
        --           value = {}
        --         }
        
        --         -- add expected states in reverse order to be more evil
        --         for i=#expected_adds,1,-1 do
        --           peer:state{
        --             path = expected_adds[i].path,
        --             value = expected_adds[i].value
        --           }
        --         end
        
        
        --         local count = 0
        --         local fetcher = peer:fetch({
        --             sort = {
        --               from = 1,
        --               to = 2
        --             }
        --           },async(function(path,event,data,index)
        --               count = count + 1
        --               if event == 'add' then
        --                 local expected = expected_adds[count]
        --                 assert.is_same(path,expected.path)
        --                 assert.is_same(data,expected.value)
        --                 assert.is_same(index,expected.index)
        --               else
        --                 assert.is_nil('should not happen')
        --               end
        --               if count == #expected_adds then
        --                 done()
        --               end
        --           end))
        
        --         finally(function() fetcher:unfetch() end)
        
        
        --       end)
        
        --     it('fetch with sort works when states are added afterwards',function(done)
        --         local expected = {
        --           -- when xcd is added
        --           {
        --             path = 'xcd',
        --             value = true,
        --             index = 1,
        --             event = 'add'
        --           },
        --           -- when ii98 is added, xcd is reordered
        --           {
        --             path = 'xcd',
        --             value = true,
        --             index = 2,
        --             event = 'change'
        --           },
        --           {
        --             path = 'ii98',
        --             value = {},
        --             index = 1,
        --             event = 'add'
        --           },
        --           -- when abc is added, ii98 is reordered and xcd  is
        --           -- removed
        --           {
        --             path = 'xcd',
        --             value = true,
        --             index = 2,
        --             event = 'remove'
        --           },
        --           {
        --             path = 'ii98',
        --             value = {},
        --             index = 2,
        --             event = 'change'
        --           },
        --           {
        --             path = 'abc',
        --             value = 123,
        --             index = 1,
        --             event = 'add'
        --           },
        --         }
        
        
        --         local count = 0
        --         local fetcher = peer:fetch({
        --             sort = {
        --               from = 1,
        --               to = 2
        --             }
        --           },async(function(path,event,data,index)
        --               count = count + 1
        --               local fetched = {
        --                 path = path,
        --                 event = event,
        --                 value = data,
        --                 index = index
        --               }
        --               assert.is_same(fetched,expected[count])
        --               if count == #expected then
        --                 done()
        --               end
        --           end))
        
        --         finally(function() fetcher:unfetch() end)
        
        --         -- add some other states which are not expected
        --         peer:state{
        --           path = 'xcd',
        --           value = true
        --         }
        
        --         peer:state{
        --           path = 'ii98',
        --           value = {}
        --         }
        
        --         peer:state{
        --           path = 'abc',
        --           value = 123
        --         }
        
        
        --       end)
        
      end)
    
  end)
