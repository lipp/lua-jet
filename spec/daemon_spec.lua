local ev = require'ev'
local jetdaemon = require'jet.daemon'
local cjson = require'cjson'
local socket = require'socket'
local jetsocket = require'jet.socket'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT') or 11122+5

setloop('ev')

local addresses_to_test

if socket.dns and socket.dns.getaddrinfo then
  addresses_to_test = socket.dns.getaddrinfo('localhost')
else
  addresses_to_test = {
    {
      family = 'inet',
      addr = '127.0.0.1'
    }
  }
end

local family_done = {}

for _,info in ipairs(addresses_to_test) do
  if family_done[info.family] then
    return
  end
  family_done[info.family] = true
  
  describe(
    'A daemon with address '..info.addr..' and family '..info.family,
    function()
      local daemon
      setup(
        function()
          daemon = jetdaemon.new
          {
            port = port,
            interface = info.addr,
          }
        end)
      
      it(
        'provides the correct interface',
        function()
          assert.is_true(type(daemon) == 'table')
          assert.is_true(type(daemon.start) == 'function')
          assert.is_true(type(daemon.stop) == 'function')
        end)
      
      it(
        'can be started',
        function()
          assert.has_not_error(
            function()
              daemon:start()
            end)
        end)
      
      it(
        'can be stopped',
        function()
          assert.has_not_error(
            function()
              daemon:stop()
            end)
        end)
      
      describe(
        'once started',
        function()
          setup(
            function()
              daemon:start()
            end)
          
          teardown(
            function()
              daemon:stop()
            end)
          
          local sock
          
          local new_sock = function()
            if info.family == 'inet6' then
              return socket.tcp6()
            else
              return socket.tcp()
            end
          end
          
          before_each(function()
              sock = new_sock()
            end)
          
          after_each(function()
              sock:shutdown()
              sock:close()
            end)
          
          it(
            'listens on specified port',
            function(done)
              sock:settimeout(0)
              assert.is_truthy(sock)
              ev.IO.new(
                async(
                  function(loop,io)
                    io:stop(loop)
                    assert.is_true(true)
                    done()
                end),sock:getfd(),ev.WRITE):start(loop)
              sock:connect(info.addr,port)
            end)
          
          it(
            'adding and removing states does not leak memory',
            function(done)
              settimeout(40)
              
              local add_msg = cjson.encode({
                  method = 'add',
                  params = {
                    path = 'foo',
                    value = string.rep('bar',200)
                  },
                  id = 'add_id'
              })
              local remove_msg = cjson.encode({
                  method = 'remove',
                  params = {
                    path = 'foo',
                  },
                  id = 'remove_id'
              })
              local count = 0
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              collectgarbage()
              local kbyte_before = collectgarbage('count')
              message_socket:send(add_msg)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    assert.is_nil(response.error)
                    assert.is_truthy(response.result)
                    if response.id == 'add_id' then
                      message_socket:send(remove_msg)
                    elseif response.id == 'remove_id' then
                      count = count + 1
                      if count == 20000 then
                        collectgarbage()
                        local kbyte_after = collectgarbage('count')
                        local kbyte_factor = kbyte_after / kbyte_before
                        assert.is_true(kbyte_factor < 1.1)
                        done()
                        return
                      end
                      message_socket:send(add_msg)
                    else
                      assert.is_nil('unexpected message id:'..response.id)
                    end
                end))
            end)
          
          it(
            'sending an Invalid Request is reported correctly',
            function(done)
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    assert.is_same(response,{
                        error = {
                          data = 123,
                          code = -32600,
                          message = 'Invalid Request'
                        }
                    })
                    done()
                end))
              message_socket:send('123')
            end)
          
          it(
            'sending an Invalid JSON is reported correctly',
            function(done)
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    assert.is_same(response,{
                        error = {
                          data = 'this is no json',
                          code = -32700,
                          message = 'Parse error',
                        }
                    })
                    done()
                end))
              message_socket:send('this is no json')
            end)
          
          it('a peer can configure persist and resume',function(done)
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    assert.is_same(response.id,1)
                    assert.is_string(response.result)
                    local resume_id = response.result
                    sock:close()
                    sock = new_sock()
                    sock:connect(info.addr,port)
                    local message_socket = jetsocket.wrap(sock)
                    message_socket:on_message(
                      async(
                        function(_,response)
                          response = cjson.decode(response)
                          assert.is_same(response.id,2)
                          -- the server has received two messages associated with this persist session
                          -- (config.persist and config.resume)
                          assert.is_same(response.result,2)
                          done()
                      end))
                    message_socket:send(cjson.encode({
                          method = 'config',
                          params = {
                            resume = {
                              id = resume_id,
                              receivedCount = 1
                            }
                          },
                          id = 2,
                    }))
                    
                end))
              message_socket:send(cjson.encode({
                    method = 'config',
                    params = {
                      persist = 0.001
                    },
                    id = 1,
              }))
            end)
          
          it('a peer can configure persist and resume (twice)',function(done)
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    assert.is_same(response.id,1)
                    assert.is_string(response.result)
                    local resume_id = response.result
                    sock:close()
                    sock = new_sock()
                    sock:connect(info.addr,port)
                    local message_socket = jetsocket.wrap(sock)
                    message_socket:on_message(
                      async(
                        function(_,response)
                          response = cjson.decode(response)
                          assert.is_same(response.id,2)
                          -- the server has received two messages associated with this persist session
                          -- (config.persist and config.resume)
                          assert.is_same(response.result,2)
                          sock:close()
                          sock = new_sock()
                          sock:connect(info.addr,port)
                          local message_socket = jetsocket.wrap(sock)
                          message_socket:on_message(
                            async(
                              function(_,response)
                                response = cjson.decode(response)
                                assert.is_same(response.id,3)
                                -- the server has received three messages associated with this persist session
                                -- (config.persist, config.resume and config.resume)
                                assert.is_same(response.result,3)
                                done()
                            end))
                          message_socket:send(cjson.encode({
                                method = 'config',
                                params = {
                                  resume = {
                                    id = resume_id,
                                    receivedCount = 2
                                  }
                                },
                                id = 3,
                          }))
                          
                      end))
                    message_socket:send(cjson.encode({
                          method = 'config',
                          params = {
                            resume = {
                              id = resume_id,
                              receivedCount = 1
                            }
                          },
                          id = 2,
                    }))
                    
                end))
              message_socket:send(cjson.encode({
                    method = 'config',
                    params = {
                      persist = 0.001
                    },
                    id = 1,
              }))
            end)
          
          
          it('a peer can configure persist and resume and missed messages are resend by daemon twice',function(done)
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    if #response > 0 then
                      response = response[1]
                    end
                    assert.is_string(response.result)
                    local resume_id = response.result
                    sock:close()
                    sock = new_sock()
                    sock:connect(info.addr,port)
                    local message_socket = jetsocket.wrap(sock)
                    message_socket:on_message(
                      async(
                        function(_,response)
                          response = cjson.decode(response)
                          assert.is_same(response,{
                              {
                                result = 5, -- five messages received by daemon yet (assoc. to the persist id)
                                id = 5, -- config.resume id
                              },
                              {
                                result = true, -- fetch set up successfully
                                id = 3,
                              },
                              {
                                method = 'fetchy', -- resumed fetched data
                                params = {
                                  path = 'dummy',
                                  value = 123,
                                  event = 'add',
                                }
                              },
                              {
                                method = 'fetchy', -- resumed fetched data
                                params = {
                                  path = 'dummy',
                                  value = 234,
                                  event = 'change',
                                }
                              },
                              {
                                result = true, -- change notification was success
                                id = 4
                              }
                          })
                          sock:close()
                          sock = new_sock()
                          sock:connect(info.addr,port)
                          local message_socket = jetsocket.wrap(sock)
                          message_socket:on_message(
                            async(
                              function(_,response)
                                response = cjson.decode(response)
                                assert.is_same(response,{
                                    {
                                      result = 6, -- six messages received by daemon yet (assoc. to the persist id)
                                      id = 6, -- config.resume id
                                    },
                                    {
                                      method = 'fetchy', -- resumed fetched data
                                      params = {
                                        path = 'dummy',
                                        value = 123,
                                        event = 'add',
                                      }
                                    },
                                    {
                                      method = 'fetchy', -- resumed fetched data
                                      params = {
                                        path = 'dummy',
                                        value = 234,
                                        event = 'change',
                                      }
                                    },
                                    {
                                      result = true, -- change notification was success
                                      id = 4
                                    }
                                })
                                -- close the socket and wait some time
                                -- to let the daemon cleanup
                                -- the dummy states assoc with this
                                -- sock. should be improved be using
                                -- *some* callback
                                sock:close()
                                ev.Timer.new(function()
                                    done()
                                  end,0.01):start(ev.Loop.default)
                            end))
                          message_socket:send(cjson.encode({
                                method = 'config',
                                params = {
                                  resume = {
                                    id = resume_id,
                                    -- pretend only 2 more messages are
                                    -- received (config and fetch setup)
                                    receivedCount = 2+2
                                  }
                                },
                                id = 6,
                          }))
                          
                      end))
                    
                    message_socket:send(cjson.encode({
                          method = 'config',
                          params = {
                            resume = {
                              id = resume_id,
                              -- pretend only config and add responses have been receveived
                              receivedCount = 2
                            }
                          },
                          id = 5,
                    }))
                    
                end))
              message_socket:send(cjson.encode({
                    {
                      method = 'config',
                      params = {
                        persist = 0.001
                      },
                      id = 1,
                    },
                    {
                      method = 'add',
                      params = {
                        path = 'dummy',
                        value = 123
                      },
                      id = 2,
                    },
                    {
                      method = 'fetch',
                      params = {
                        id = 'fetchy',
                        matches = {'.*'}
                      },
                      id = 3,
                    },
                    {
                      method = 'change',
                      params = {
                        path = 'dummy',
                        value = 234
                      },
                      id = 4,
                    },
              }))
            end)
          
          it('a peer can configure persist and resume and missed messages are resend by daemon',function(done)
              sock:connect(info.addr,port)
              local message_socket = jetsocket.wrap(sock)
              message_socket:on_message(
                async(
                  function(_,response)
                    response = cjson.decode(response)
                    if #response > 0 then
                      response = response[1]
                    end
                    assert.is_string(response.result)
                    local resume_id = response.result
                    sock:close()
                    sock = new_sock()
                    sock:connect(info.addr,port)
                    local message_socket = jetsocket.wrap(sock)
                    message_socket:on_message(
                      async(
                        function(_,response)
                          response = cjson.decode(response)
                          assert.is_same(response,{
                              {
                                result = 5, -- five messages received by daemon yet (assoc. to the persist id)
                                id = 5, -- config.resume id
                              },
                              {
                                result = true, -- fetch set up successfully
                                id = 3,
                              },
                              {
                                method = 'fetchy', -- resumed fetched data
                                params = {
                                  path = 'dummy',
                                  value = 123,
                                  event = 'add',
                                }
                              },
                              {
                                method = 'fetchy', -- resumed fetched data
                                params = {
                                  path = 'dummy',
                                  value = 234,
                                  event = 'change',
                                }
                              },
                              {
                                result = true, -- change notification was success
                                id = 4
                              }
                          })
                          done()
                      end))
                    message_socket:send(cjson.encode({
                          method = 'config',
                          params = {
                            resume = {
                              id = resume_id,
                              -- pretend only config and add responses have been receveived
                              receivedCount = 2
                            }
                          },
                          id = 5,
                    }))
                    
                end))
              message_socket:send(cjson.encode({
                    {
                      method = 'config',
                      params = {
                        persist = 0.001
                      },
                      id = 1,
                    },
                    {
                      method = 'add',
                      params = {
                        path = 'dummy',
                        value = 123
                      },
                      id = 2,
                    },
                    {
                      method = 'fetch',
                      params = {
                        id = 'fetchy',
                        matches = {'.*'}
                      },
                      id = 3,
                    },
                    {
                      method = 'change',
                      params = {
                        path = 'dummy',
                        value = 234
                      },
                      id = 4,
                    },
              }))
            end)
          
          
          local req_resp_test = function(desc)
            local requests = desc.requests
            local responses = desc.responses
            it(
              desc.title,
              function(done)
                sock:connect(info.addr,port)
                local message_socket = jetsocket.wrap(sock)
                
                local count = 0
                message_socket:on_message(
                  async(
                    function(_,response)
                      response = cjson.decode(response)
                      count = count + 1
                      assert.is_same(response,responses[count])
                      if count == #responses then
                        done()
                      end
                  end))
                for _,request in ipairs(requests) do
                  message_socket:send(cjson.encode(request))
                end
              end)
          end
          
          req_resp_test({
              title = 'adding a state twice fails and "pathAlreadyExists" is reported',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'abc',
                    value = 123
                  },
                  id = 1
                },
                {
                  method = 'add',
                  params = {
                    path = 'abc',
                    value = 123
                  },
                  id = 2
                },
              },
              responses = {
                {
                  id = 1,
                  result = true
                },
                {
                  id = 2,
                  error = {
                    data = {
                      pathAlreadyExists = 'abc'
                    },
                    code = -32602,
                    message = 'Invalid params',
                  }
                }
          }})
          
          req_resp_test({
              title = 'adding a state twice fails and "pathAlreadyExists" is reported / variant with less message ids',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'abc',
                    value = 123
                  }
                },
                {
                  method = 'add',
                  params = {
                    path = 'abc',
                    value = 123
                  },
                  id = 1
                },
              },
              responses = {
                {
                  id = 1,
                  error = {
                    data = {
                      pathAlreadyExists = 'abc'
                    },
                    code = -32602,
                    message = 'Invalid params',
                  }
                }
          }})
          
          req_resp_test({
              title = 'add / change / remove',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'abc',
                    value = 123
                  },
                  id = 1
                },
                {
                  method = 'change',
                  params = {
                    path = 'abc',
                    value = 345
                  },
                  id = 2
                },
                {
                  method = 'remove',
                  params = {
                    path = 'abc',
                  },
                  id = 3
                },
              },
              responses = {
                {
                  id = 1,
                  result = true,
                },
                {
                  id = 2,
                  result = true,
                },
                {
                  id = 3,
                  result = true,
                }
              }
          })
          
          req_resp_test({
              title = 'removing a not existing path gives error "pathNotExists"',
              requests = {
                {
                  method = 'remove',
                  params = {
                    path = 'abc',
                  },
                  id = 1
                }
              },
              responses = {
                {
                  id = 1,
                  error = {
                    data = {
                      pathNotExists = 'abc'
                    },
                    code = -32602,
                    message = 'Invalid params',
                  }
                }
              }
          })
          
          req_resp_test({
              title = 'calling add without a path gives an error',
              requests = {
                {
                  method = 'add',
                  params = {
                    value = 123,
                  },
                  id = 1
                }
              },
              responses = {
                {
                  id = 1,
                  error = {
                    data = {
                      missingParam = 'path',
                      got = {
                        value = 123
                      }
                    },
                    code = -32602,
                    message = 'Invalid params',
                  }
                }
              }
          })
          
          req_resp_test({
              title = 'fetch with path matching works',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'a',
                    value = 123,
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'b',
                    value = 456,
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'c',
                    value = 789,
                  },
                },
                {
                  method = 'fetch',
                  params = {
                    path = {
                      unequalsAllOf = {'A','^C$'},
                      caseInsensitive = true,
                      contains = 'B'
                    },
                    id = 'testFetch'
                  },
                }
              },
              responses = {
                {
                  method = 'testFetch',
                  params = {
                    event = 'add',
                    path = 'b',
                    value = 456
                  }
                }
              }
          })
          
          req_resp_test({
              title = 'fetch with valueField array works',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'num',
                    value = 123,
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'bob',
                    value = {
                      age = 10,
                      weight = 20
                    },
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'peter',
                    value = {
                      age = 10,
                      weight = 22
                    },
                  },
                },
                {
                  method = 'fetch',
                  params = {
                    valueField = {
                      age = {
                        lessThan = 30
                      },
                      weight = {
                        greaterThan = 20
                      }
                    },
                    id = 'testFetch2'
                  },
                },
              },
              responses = {
                {
                  method = 'testFetch2',
                  params = {
                    event = 'add',
                    path = 'peter',
                    value = {
                      age = 10,
                      weight = 22
                    }
                  }
                }
              }
          })
          
          req_resp_test({
              title = 'fetch with sort by value works',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'a',
                    value = 123,
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'b',
                    value = 456,
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'c',
                    value = 789,
                  },
                },
                {
                  method = 'fetch',
                  params = {
                    id = 'testFetch3',
                    sort = {
                      byValue = 'number'
                    }
                  },
                }
              },
              responses = {
                {
                  method = 'testFetch3',
                  params = {
                    n = 3,
                    changes = {
                      {
                        value = 123,
                        path = 'a',
                        index = 1
                      },
                      {
                        value = 456,
                        path = 'b',
                        index = 2
                      },
                      {
                        value = 789,
                        path = 'c',
                        index = 3
                      }
                    }
                  }
                }
              }
          })
          
          req_resp_test({
              title = 'fetch with sort by valueField works',
              requests = {
                {
                  method = 'add',
                  params = {
                    path = 'a',
                    value = {
                      age = 123,
                    }
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'b',
                    value = {
                      age = 456,
                    }
                  },
                },
                {
                  method = 'add',
                  params = {
                    path = 'c',
                    value = {
                      age = 789,
                    }
                  },
                },
                {
                  method = 'fetch',
                  params = {
                    id = 'testFetch3',
                    sort = {
                      byValueField = {
                        age = 'number'
                      }
                    }
                  },
                }
              },
              responses = {
                {
                  method = 'testFetch3',
                  params = {
                    n = 3,
                    changes = {
                      {
                        value = {age = 123},
                        path = 'a',
                        index = 1
                      },
                      {
                        value = {age = 456},
                        path = 'b',
                        index = 2
                      },
                      {
                        value = {age = 789},
                        path = 'c',
                        index = 3
                      }
                    }
                  }
                }
              }
          })
          
          req_resp_test({
              title = 'calling an invalid service reports error',
              requests = {
                {
                  method = 'foo',
                  id = 123
                },
              },
              responses = {
                {
                  id = 123,
                  error = {
                    data = 'foo',
                    code = -32601,
                    message = 'Method not found'
                  }
                }
          }})
          
          req_resp_test({
              title = 'sending non jsonrpc JSON gives error with id',
              requests = {
                {
                  foo = 'bar',
                  id = 123
                },
              },
              responses = {
                {
                  id = 123,
                  error = {
                    data = {
                      foo = 'bar',
                      id = 123
                    },
                    code = -32600,
                    message = 'Invalid Request'
                  }
                }
          }})
          
          req_resp_test({
              title = 'sending non jsonrpc JSON gives error without id',
              requests = {
                {
                  foo = 'bar',
                },
              },
              responses = {
                {
                  error = {
                    data = {
                      foo = 'bar',
                    },
                    code = -32600,
                    message = 'Invalid Request'
                  }
                }
          }})
          
        end)
    end)
  
end
