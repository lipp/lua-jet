package = 'jet'
version = 'scm-1'
source = {
  url = 'git://github.com/lipp/jet.git',
}
description = {
  summary = 'A simple JSON based bus.',
  homepage = 'http://github.com/lipp/jet',
  license = 'MIT/X11'
}
dependencies = {
  'lua >= 5.1',
  'lua-cjson >= 1.0',
  'lua-cmsgpack',
  'luasocket',
  'lua-ev',
  'lpack'
}
build = {
  type = 'none',
  install = {
    lua = {
      ['jet'] = 'src/jet.lua',
      ['jet.peer'] = 'src/jet/peer.lua',
      ['jet.socket'] = 'src/jet/socket.lua',
      ['jet.daemon'] = 'src/jet/daemon.lua'
    },
    bin = {
      'bin/jetd.lua',
    }
  }
}
