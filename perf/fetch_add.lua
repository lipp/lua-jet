#!/usr/bin/env lua
-- Measure add-fetch-notification throughput and the impact of a growing
-- number of fetchers (which dont match).
-- The time is measured for adding and removing <count> states.
-- Afterwards, the number of fetchers is incremented by 20 and the test is repeated.
-- Note that the add/remove peer stuff benefits from batching messages!
--local profiler = require'profiler'
local jet = require'jet'
local ev = require'ev'
local step = require'step'
local cjson = require'cjson'

local port = 10112

local daemon = jet.daemon.new({
    port = port,
    crit = print
})

daemon:start()

local fetch_peer = jet.peer.new({
    port = port
})

local count = 10000
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
        state_peer:fetch('^'..last_path..'$',function(path,event,value,fetcher)
            assert(path == last_path)
            if event == 'add' then
              assert(not added)
              added = true
              for i,state in ipairs(states) do
                state:remove()
              end
            elseif event == 'remove' then
              fetcher:unfetch({
                  success = function()
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
        
        for i=1,count do
          states[i] = state_peer:state({
              path = long_path_prefix..i,
              value = 123
          })
        end
      end
  })
end

local fetchers = 1

local print_and_increment_fetchers = function(dt)
  print(math.floor(count/dt),'add-remove/sec @'..fetchers..' fetchers')
  for i=1,20 do
    fetch_peer:fetch('^'..long_path_prefix..fetchers..'f$',function() end)
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

step.new({
    try = tries,
    finally = function()
      fetch_peer:close()
      daemon:stop()
    end,
    catch = function(step,...)
      print(cjson.encode({...}))
    end
})()

--profiler.start()

ev.Loop.default:loop()

--profiler.stop()
