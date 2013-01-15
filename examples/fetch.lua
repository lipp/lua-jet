#!/usr/bin/env lua
-- fetches all available jet nodes,states and methods and prints
-- the basic notification info
local jet = require'jet.peer'.new()
local cjson = require'cjson'
local info = function(path,event,data)
   print(path,event,cjson.encode(data))
end
jet:fetch('.*',info)
jet:loop()

