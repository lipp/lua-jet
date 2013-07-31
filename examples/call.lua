#!/usr/bin/env lua
local cjson = require'cjson'
local path = arg[1]
local args = cjson.decode(arg[2])
local ip = arg[3]
local port = arg[4]

local peer = require'jet.peer'.new{ip=ip,port=port,sync=true}
local result = peer:call(path,args)

print(cjson.encode(result))


