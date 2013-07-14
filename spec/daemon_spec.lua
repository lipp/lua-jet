local ev = require'ev'
local jetdaemon = require'jet.daemon'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT') or 11122+5

setloop('ev')

describe(
  'A daemon',
  function()
    local daemon
    setup(
      function()
        daemon = jetdaemon.new
        {
          port = port,
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
            local sock = socket.tcp()
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
            sock:connect('127.0.0.1',port)
          end)
      end)
  end)


