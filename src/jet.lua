local peer = require'jet.peer'
local daemon = require'jet.daemon'

local jet = {
  peer = peer,
  daemon = daemon,
  new = peer.new,
  _VERSION = '0.10'
}

return jet
