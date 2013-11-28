#!/usr/bin/env lua
-- example program for manually testing persistant peers
local jet = require'jet'
local ev = require'ev'

assert(arg[1],'ip exepected')

local peer = jet.peer.new({
    ip = arg[1],
    persist = 10,
})

local tick_tack = peer:state({
    path = 'tick_tack',
    value = 1
})

ev.Timer.new(function()
    local new = tick_tack:value() + 1
    print(new)
    tick_tack:value(new)
  end,1,1):start(ev.Loop.default)

peer:loop()
