#!/usr/bin/env lua

local ev = require'ev'

local daemon = false
local ws_port = 11123
local port = 11122
local ffi

for _,opt in ipairs(arg) do
  if opt == '-d' or opt == '--daemon' then
    ffi = require'ffi'
    if not ffi then
      log('daemonizing failed: ffi (luajit) is required.')
      os.exit(1)
    end
    ffi.cdef'int daemon(int nochdir, int noclose)'
  elseif opt:match('%-w(%d+)') then
    ws_port = opt:match('%-w(%d+)')
  elseif opt:match('%-p(%d+)') then
    port = opt:match('%-p(%d+)')
  end
end

print(daemon,ws_port,port)

local daemon = require'jet.daemon'.new
{
  ws_port = ws_port,
  port = port
}
daemon:start()

if daemon then
  ffi.C.daemon(1,1)
end

ev.Loop.default:loop()
