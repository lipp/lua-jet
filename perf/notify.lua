#!/usr/bin/env lua
-- Measure fetch-notification throughput and the impact of a growing
-- number of fetchers (which dont match).
-- This (unrealistic) setup can not benefit from message batches.
local this_dir = arg[0]:match('(.+/)[^/]+%.lua') or './'
package.path = this_dir..'../src/'..package.path

local profiler = require'profiler'
local jet = require'jet'
local ev = require'ev'

local port = 10112

local daemon = jet.daemon.new({
    port = port,
    crit = print
})

daemon:start()

local peer = jet.peer.new({
    port = port
})

local long_path_prefix = string.rep('foobar',10)

local count_state = peer:state({
    path = long_path_prefix..'COUNT',
    value = 0
})

local notifier = 10

local other_states = {}
for i=1,notifier do
  other_states[i] = peer:state({
      path = long_path_prefix..'os'..i,
      value = i
  })
end

local count = 1

-- Creates an exact path based count fetcher
-- which increments the count immediatly.
peer:fetch({path={equals=count_state:path()}},function(path,event,value)
    assert(value == (count-1))
    count_state:value(count)
    count = count + 1
    for _,other in ipairs(other_states) do
      other:value(other:value() + 1)
    end
  end)

local dt = 3
local fetchers = 1
local last = 0

local sighandler = ev.Signal.new(function()
    os.exit(1)
  end,2)
sighandler:start(ev.Loop.default)

-- After 'dt' seconds, print the current throughput results and
-- restart the test with 20 more peers.
ev.Timer.new(function(loop,timer)
    -- receiving a changed value actually implies 2 messages
    print(math.floor((count-last)*notifier/dt),'fetch-notify/sec @'..fetchers..' fetchers')
    last = count
    if fetchers > 201 then
      peer:close()
      daemon:stop()
      timer:stop(loop)
      sighandler:stop(loop)
    else
      for i=1,20 do
        peer:fetch({path = {equals = long_path_prefix..fetchers}},function() end)
        fetchers = fetchers + 1
      end
    end
  end,dt,dt):start(ev.Loop.default)

ev.Signal.new(function()
    os.exit(1)
  end,2):start(ev.Loop.default)

--profiler.start()

ev.Loop.default:loop()

--profiler.stop()
