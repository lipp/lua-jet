#!/usr/bin/env lua
-- fetches all available jet nodes,states and methods and prints
-- the basic notification info
local jet = require'jet.peer'.new()
local info = function(notification)
   print(notification.path,notification.event,notification.data)
end
jet:fetch('.*',info)
jet:loop()

