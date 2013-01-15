package = 'jet'
version = 'scm-1'
source = {
  url = 'git://github.com/lipp/jet.git',
}
description = {
  summary = '',
  homepage = 'http://github.com/lipp/jet',
  license = 'MIT/X11'
}
dependencies = {
  'lua >= 5.1',
  'lua-cjson >= 1.0',
  'luasocket',
  'lua-ev',
  'lpack'
}
build = {
  type = 'none',
  install = {
    lua = {
      ['jet.peer'] = 'jet/peer.lua',
      ['jet.socket'] = 'jet/socket.lua',
      ['jet.daemon'] = 'jet/daemon.lua'
    },
    bin = {
      'bin/jetd.lua',
      'bin/jet-ws.lua'  
    }
  }
}
