local peer = require'jet.peer'
local daemon = require'jet.daemon'

module('jet')

local jet = {
  peer = peer,
  daemon = daemon,
  new = peer.new
}

return jet
