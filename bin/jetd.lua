#!/usr/bin/env lua

local ev = require'ev'

local start_as_daemon = false
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
    start_as_daemon = true
  elseif opt:match('%-w(%d+)') then
    ws_port = opt:match('%-w(%d+)')
  elseif opt:match('%-p(%d+)') then
    port = opt:match('%-p(%d+)')
  elseif opt == '-h' or opt == '--help' then
    print('usage: jetd.lua [-d|--daemon] [-w<wsport>] [-p<rawport>] [-h|--help]')
    os.exit(0)
  end
end

local print_with_level = function(level)
  return function(...)
    print('jetd',level,...)
  end
end

local daemon = require'jet.daemon'.new{
  ws_port = ws_port,
  port = port,
  crit = print_with_level('crit'),
  log = print_with_level('log'),
  info = print_with_level('info'),
  debug = print_with_level('debug'),
}

daemon:start()

if start_as_daemon then
  ffi.C.daemon(1,1)
end

ev.Loop.default:loop()
