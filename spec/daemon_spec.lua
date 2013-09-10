local ev = require'ev'
local jetdaemon = require'jet.daemon'
local socket = require'socket'
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
        end)
    end)
  
end
