#!/usr/bin/env lua
-- fetches all available jet nodes,states and methods and prints
-- the basic notification info

local exp = arg[1] or '.*'
local ip = arg[2]
local port = arg[3]

local jet = require'jet.peer'.new{ip=ip,port=port}
local cjson = require'cjson'
local info = function(path,event,data)
  print(path,event,cjson.encode(data))
end
jet:fetch(exp,info)
jet:loop()

