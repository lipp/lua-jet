#!/usr/bin/env lua

local ev = require'ev'

local daemon = require'jet.daemon'.new()
daemon:start()

for _,opt in ipairs(arg) do
   if opt == '-d' or opt == '--daemon' then      
      local ffi = require'ffi'
      if not ffi then
         log('daemonizing failed: ffi (luajit) is required.')
         os.exit(1)
      end
      ffi.cdef'int daemon(int nochdir, int noclose)'
      assert(ffi.C.daemon(1,1)==0)      
   end
end

ev.Loop.default:loop()
