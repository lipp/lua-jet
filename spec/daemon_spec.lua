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
          
          it(
            'listens on specified port',
            function(done)
              local sock
              if info.family == 'inet6' then
                sock = socket.tcp6()
              else
                sock = socket.tcp()
              end
              sock:settimeout(0)
              assert.is_truthy(sock)
              ev.IO.new(
                async(
                  function(loop,io)
                    io:stop(loop)
                    assert.is_true(true)
                    sock:shutdown()
                    sock:close()
                    done()
                end),sock:getfd(),ev.WRITE):start(loop)
              sock:connect(info.addr,port)
            end)
          
          it(
            'adding and removing states does not leak memory',
            function(done)
              settimeout(20)
              local sock
              if info.family == 'inet6' then
                sock = socket.tcp6()
              else
                sock = socket.tcp()
              end
              assert.is_truthy(sock)
              finally(function()
                  sock:shutdown()
                  sock:close()
                end)
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
        end)
    end)
  
end
