#!/usr/bin/env lua
-- fetches all available jet nodes,states and methods and prints
-- the basic notification info

local exp = arg[1] or {}
local ip = arg[2]
local port = arg[3]

local cjson = require'cjson'
local peer = require'jet.peer'.new{ip=ip,port=port}

local is_json,exp_json = pcall(cjson.decode,exp)
if is_json then
  exp = exp_json
end

peer:fetch(exp,function(path,event,data)
    print(path,event,cjson.encode(data))
  end)

peer:loop()

