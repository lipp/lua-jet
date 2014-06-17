#!/usr/bin/env lua
local peer = require'jet.peer'.new({
    -- url = 'ws://jet.nodejitsu.com:80',
    name = 'players',
    on_connect = function()
      print('connected to Jet Daemon')
    end
})
local ev = require'ev'

local players = {
  {
    name = 'John Doe',
    age = 32,
    score = 0
  },
  {
    name = 'Marky Mark',
    age = 99,
    score = 0
  },
  
  {
    name = 'Paul',
    age = 12,
    score = 0
  },
  {
    name = 'Peter Pole',
    age = 32,
    score = 0
  },
  {
    name = 'Bob Maake',
    age = 44,
    score = 0
  },
  {
    name = 'John Doe',
    age = 32,
    score = 0
  },
  {
    name = 'Ben Hurel',
    age = 67,
    score = 0
  },
  {
    name = 'Junior',
    age = 1,
    score = 0
  },
  {
    name = 'Jim Bim',
    age = 34,
    score = 0
  },
  {
    name = 'Moni Kart',
    age = 32,
    score = 0
  },
  {
    name = 'April March',
    age = 19,
    score = 0
  },
  {
    name = 'Sunny Cloud',
    age = 35,
    score = 0
  },
  {
    name = 'Alex P',
    age = 87,
    score = 0
  },
  {
    name = 'The GREATEST',
    age = 2,
    score = 0
  }
}

local player_states = {}

for i,player in ipairs(players) do
  player_states[i] = peer:state({value = players[i],path='player/#'..i})
end

ev.Timer.new(function()
    local i = math.random(#players)
    local player = player_states[i]
    local val = player:value()
    val.score = val.score + math.random(1,1000)
    player:value(val)
  end,2,2):start(ev.Loop.default)

peer:loop()
