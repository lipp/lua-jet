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

for _,info in ipairs(addresses_to_test) do
  
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
            print = function() end
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
          
          before_each(function()
              if info.family == 'inet6' then
                sock = socket.tcp6()
              else
                sock = socket.tcp()
              end
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
              settimeout(20)
              
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
              local message_socket = jetsocket.wrap(sock)
              sock:connect(info.addr,port)
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
              message_socket:read_io():start(loop)
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
              message_socket:read_io():start(loop)
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
              message_socket:read_io():start(loop)
              message_socket:send('this is no json')
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
                message_socket:read_io():start(loop)
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
              title = 'fetch with unmatch,match,equalsNot,caseInsensitive works',
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
                    unmatch = {'A'},
                    equalsNot = {'C'},
                    caseInsensitive = true,
                    match = {'B'},
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
              title = 'fetch with where array works',
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
                    match = {'.*'},
                    where = {
                      {
                        prop = 'age',
                        value = 30,
                        op = 'lessThan'
                      },
                      {
                        prop = 'weight',
                        value = 20,
                        op = 'greaterThan'
                      }
                    },
                    id = 'testFetch2'
                  },
                }
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
                    match = {'.*'},
                    id = 'testFetch3',
                    sort = {
                      byValue = true
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
          
        end)
    end)
  
end
