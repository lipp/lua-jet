#!/usr/bin/env lua
-- fetches all available jet nodes,states and methods and prints
-- the basic notification info

local cjson = require'cjson'

local peer = require'jet.peer'.new({
    url = 'ws://jet.nodejitsu.com:80'
})

peer:fetch({},function(path,event,data)
    print(path,event,cjson.encode(data))
  end)

peer:loop()
