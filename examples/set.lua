#!/usr/bin/env lua
local cjson = require'cjson'
local path = arg[1]
local value = cjson.decode(arg[2])
local ip = arg[3]
local port = arg[4]

local peer = require'jet.peer'.new{ip=ip,port=port,sync=true}
peer:set(path,value)


