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
  'zbus'
}
build = {
  type = 'none',
  install = {
    lua = {
      ["jet"] = 'jet.lua'
    },
    bin = {
      'jetcached.lua'
    }
  }
}
