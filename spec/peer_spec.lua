local ev = require'ev'
local jetdaemon = require'jet.daemon'
local jetpeer = require'jet.peer'
local loop = ev.Loop.default
local socket = require'socket'
local port = os.getenv('JET_PORT') or 11122+5
local ws_port = port + 100
local dt = 0.05

setloop('ev')

create_peer_tests = function(config)
  
  describe(
    'A peer basic tests '.. (config.url and '(Websocket)' or ''),
    function()
      local daemon
      local peer
      setup(function()
          daemon = jetdaemon.new{
            port = port,
            ws_port = ws_port,
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
            port = config.port,
            url = config.url,
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
                port = config.port,
                url = config.url,
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
                {path = {equals = 'test'}},
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
                port = config.port,
                url = config.url,
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
                {value={equals=states.test:value()}},
                async(function(fpath,fevent,fvalue)
                    count = count + 1
                    assert.is_equal(expected[count].event,fevent)
                    assert.is_equal(expected[count].value,fvalue)
                    expected[count].action()
                end))
              finally(function() fetcher:unfetch() end)
            end)
          
          it('can fetch states with "endsWith" and "value" "equalsNot"',function(done)
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
                  path = {
                    endsWith = 'hobby',
                  },
                  value = {
                    equalsNot = states.peters_hobby:value()
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
          
          it('can fetch states with "startsWidth" and "valueField"',function(done)
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
                  path = {
                    startsWith = 'persons/',
                  },
                  valueField = {
                    age = {
                      lessThan = 40
                    }
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
          
          it('can fetch states with no path matcher "valueField" "equals"',function(done)
              local fetcher = peer:fetch(
                {valueField={
                    name = {
                      equals='peter'
                    }
                }},
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
                  path = {
                    equals = 'persons/1/HOBBY',
                    caseInsensitive = true,
                  }
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
                port = config.port,
                url = config.url,
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
          
          it('call method passes correct args and result',function(done)
              local m = peer:method
              {
                path = 'abc3',
                call = function(arg1,arg2)
                  return 123
                end
              }
              finally(function()
                  m:remove()
                end)
              peer:call('abc3',{4,25},{
                  success = async(function(result)
                      assert.is_same(result,123)
                      done()
                    end),
                  error = async(function(err)
                      assert.is_nil(err or 'should not happen')
                    end)
              })
            end)
          
          it('call method forwards "non-json-rpc" error as "Internal error"',function(done)
              local m = peer:method
              {
                path = 'abc4',
                call = function()
                  error('terror')
                end
              }
              finally(function()
                  m:remove()
                end)
              peer:call('abc4',{},{
                  success = async(function(result)
                      assert.is_nil(result or 'should not happen')
                    end),
                  error = async(function(err)
                      assert.is_same(err.message,'Internal error')
                      assert.is_same(err.code,-32603)
                      assert.is_truthy(err.data:match('terror'))
                      done()
                    end)
              })
            end)
          
          it('call method forwards json-rpc-error unchanged',function(done)
              local m = peer:method
              {
                path = 'abc5',
                call = function()
                  error({message='foo',code=9182,data='bar'})
                end
              }
              finally(function()
                  m:remove()
                end)
              peer:call('abc5',{},{
                  success = async(function(result)
                      assert.is_nil(result or 'should not happen')
                    end),
                  error = async(function(err)
                      assert.is_same(err.message,'foo')
                      assert.is_same(err.code,9182)
                      assert.is_same(err.data,'bar')
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
                  port = config.port,
                  url = config.url,
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
  
end

create_peer_tests({port=port})
create_peer_tests({url='ws://127.0.0.1:' .. ws_port})


local ipv6_localhost_addr

if socket.dns and socket.dns.getaddrinfo then
  for _,info in pairs(socket.dns.getaddrinfo('localhost')) do
    if info.family == 'inet6' then
      ipv6_localhost_addr = info.addr
    end
  end
end

if ipv6_localhost_addr then
  
  describe('ipv6 stuff',function()
      local daemon
      local peer
      setup(function()
          daemon = jetdaemon.new{
            port = port,
            interface = ipv6_localhost_addr,
            print = function() end
          }
          daemon:start()
        end)
      
      teardown(function()
          daemon:stop()
          if peer then
            peer:close()
          end
        end)
      
      it('The jet.peer can connect to the ipv6 localhost addr '..ipv6_localhost_addr..' and on_connect gets called',function(done)
          peer = jetpeer.new
          {
            port = port,
            ip = ipv6_localhost_addr,
            on_connect = async(function(p)
                assert.is_equal(peer,p)
                done()
              end)
          }
        end)
      
    end)
end
