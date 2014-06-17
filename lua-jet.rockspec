package = 'lua-jet'
version = '@VERSION@-1'

source = {
  url = 'git://github.com/lipp/lua-jet.git',
  tag = '@VERSION@'
}

description = {
  summary = 'The JSON Bus. Daemon and Peer implementations for Lua.',
  homepage = 'http://jetbus.io',
  license = 'MIT/X11'
}

dependencies = {
  'lua >= 5.1',
  'lua-cjson >= 1.0',
  'lua-websockets',
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
      ['jet.utils'] = 'src/jet/utils.lua',
      ['jet.daemon'] = 'src/jet/daemon.lua',
      ['jet.daemon.value_matcher'] = 'src/jet/daemon/value_matcher.lua',
      ['jet.daemon.path_matcher'] = 'src/jet/daemon/path_matcher.lua',
      ['jet.daemon.radix'] = 'src/jet/daemon/radix.lua',
      ['jet.daemon.sorter'] = 'src/jet/daemon/sorter.lua',
      ['jet.daemon.fetcher'] = 'src/jet/daemon/fetcher.lua',
    },
    bin = {
      'bin/jetd.lua',
    }
  }
}
