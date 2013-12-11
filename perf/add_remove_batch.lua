#!/usr/bin/env lua
-- Measure add-fetch-notification throughput and the impact of a growing
-- number of fetchers (which dont match).
-- The time is measured for adding and removing <count> states.
-- Afterwards, the number of fetchers is incremented by 20 and the test is repeated.
-- Note that the add/remove peer stuff benefits from batching messages!
-- local profiler = require'profiler'
local this_dir = arg[0]:match('(.+/)[^/]+%.lua') or './'
package.path = this_dir..'../src/'..package.path

local jet = require'jet'
local ev = require'ev'
local step = require'step'
local cjson = require'cjson'

local port = 10112

local count = 30000

for _,batchsize in ipairs({count/1,count/1000,count/10000,1}) do
  
  local daemon = jet.daemon.new({
      port = port,
      crit = print
  })
  
  daemon:start()
  
  local fetch_peer = jet.peer.new({
      port = port
  })
  
  local long_path_prefix = string.rep('foobar',10)
  
  local add_remove = function(done)
    local state_peer = jet.peer.new({
        port = port,
        log = function(...)
          print('problem',...)
        end,
        on_connect = function(state_peer)
          
          local last_path = long_path_prefix..tostring(count)
          local states = {}
          local added
          
          local t_start
          state_peer:fetch({path={equals=last_path}},function(path,event,value,fetcher)
              assert(path == last_path)
              if event == 'remove' then
                fetcher:unfetch({
                    success = function()
                      states = {}
                      local t_end = socket.gettime()
                      state_peer:close()
                      collectgarbage()
                      done(t_end - t_start)
                    end,
                    error = function()
                      assert(false,'arg')
                    end
                })
              end
            end)
          
          t_start = socket.gettime()
          
          local add_some_states
          local x = 0
          add_some_states = function()
            state_peer:batch(function()
                for i=1,batchsize do
                  x = x + 1
                  table.insert(states,state_peer:state({
                        path = long_path_prefix..x,
                        value = 123
                        },i == batchsize and {
                        success = function()
                          if #states < count then
                            add_some_states()
                          else
                            for i,state in ipairs(states) do
                              state:remove()
                            end
                          end
                        end
                  }))
                end
              end)
          end
          add_some_states()
        end
    })
  end
  
  local fetchers = 1
  
  local print_and_increment_fetchers = function(dt)
    print(math.floor(count/dt),'add-remove/sec @'..fetchers..' fetchers','batchsize:'..batchsize)
    for i=1,20 do
      fetch_peer:fetch({path = {equals=long_path_prefix..fetchers}},function() end)
      fetchers = fetchers + 1
    end
  end
  
  
  local tries = {}
  
  for i=1,10 do
    tries[i] = function(step)
      add_remove(function(dt)
          print_and_increment_fetchers(dt)
          step.success()
        end)
    end
  end
  
  local sighandler = ev.Signal.new(function()
      os.exit(1)
    end,2)
  sighandler:start(ev.Loop.default)
  
  step.new({
      try = tries,
      finally = function()
        fetch_peer:close()
        daemon:stop()
        sighandler:stop(ev.Loop.default)
      end,
      catch = function(step,...)
        print(cjson.encode({...}))
      end
  })()
  
  --profiler.start()
  
  ev.Loop.default:loop()
end

--profiler.stop()
