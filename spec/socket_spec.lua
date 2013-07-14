local ev = require'ev'
local socket = require'socket'
local jetsocket = require'jet.socket'
local loop = ev.Loop.default
local port = os.getenv('JET_PORT') or 12372

setloop('ev')

describe(
  'Echo test with message socket',
  function()
    local echo_server_io
    local echo_listener
    local accepted = {}
    setup(
      function()
        echo_listener = socket.bind('*',port)
        local accept_echo = function()
          local sock = echo_listener:accept()
          local current = jetsocket.wrap(sock)
          current:on_message(
            function(wrapped,message)
              wrapped:send(message)
            end)
          current:read_io():start(loop)
          accepted[#accepted+1] = current
        end
        echo_listener:settimeout(0)
        echo_server_io = ev.IO.new(
          accept_echo,
          echo_listener:getfd(),
        ev.READ)
        echo_server_io:start(loop)
      end)
    
    teardown(
      function()
        echo_server_io:stop(loop)
        for i in ipairs(accepted) do
          accepted[i]:close()
        end
        echo_listener:close()
      end)
    
    local sock
    local echo = function(message,done)
      local f = function(done)
        local wrapped = jetsocket.wrap(sock)
        wrapped:on_message(
          async(
            function(wrapped,echoed)
              assert.is.same(message,echoed)
              wrapped:close()
              done()
          end))
        wrapped:read_io():start(loop)
        wrapped:send(message)
      end
      return f
    end
    
    before_each(
      function()
        sock = socket.connect('localhost',port)
      end)
    
    after_each(
      function()
        sock:shutdown()
        sock:close()
      end)
    
    it('can echo ascii',echo('ablbalblasdkjhsdkuhqdkkbjasdkjheiurq,jwek'))
    it('can echo binary',echo(string.char(0,0,0,0,1,0,10,230,0)))
    it('can echo many messages',
      function(done)
        local wrapped = jetsocket.wrap(sock)
        local count = 0
        local messages = {
          '123','sjygdjhgsudkshd','askjdhksahdkshkshdkshdkhaiuysd'
        }
        
        wrapped:on_message(
          async(
            function(wrapped,echoed)
              count = count + 1
              assert.is.same(messages[count],echoed)
              if count == 3 then
                wrapped:close()
                done()
              end
          end))
        
        wrapped:read_io():start(loop)
        
        for _,message in ipairs(messages) do
          wrapped:send(message)
        end
      end)
  end)

describe(
  'Event test with message socket',
  function()
    local server_io
    local listener
    local on_accept
    setup(
      function()
        listener,err = socket.bind('*',port)
        local accept = function()
          local sock = listener:accept()
          sock:shutdown()
          sock:close()
        end
        listener:settimeout(0)
        server_io = ev.IO.new(
          accept,
          listener:getfd(),
        ev.READ)
        server_io:start(loop)
      end)
    teardown(
      function()
        server_io:stop(loop)
        listener:close()
      end)
    
    
    it('should fire on_close event',
      function(done)
        local wrapped
        local sock = socket.tcp()
        assert.is_truthy(sock)
        sock:settimeout(0)
        ev.IO.new(
          async(
            function(loop,connect_io)
              connect_io:stop(loop)
              wrapped = jetsocket.wrap(sock)
              wrapped:on_close(
                async(
                  function()
                    assert.is_true(true)
                    wrapped:close()
                    done()
                end))
              wrapped:read_io():start(loop)
          end),sock:getfd(),ev.WRITE):start(loop)-- connect io
        sock:connect('127.0.0.1',port)
        finally(function()
            sock:shutdown()
            sock:close()
            if wrapped then
              wrapped:read_io():stop(loop)
            end
          end)
      end)
  end)


