rockspec_format = '3.0'
package = 'niemify'
version = '2.0.0-1'
source = {
  url = 'git+https://github.com/ObsaSiyo/niemify.git',
  tag = 'v2.0.0',
}
description = {
  summary = 'Ordered XML and JSON conversion with local XSD validation',
  homepage = 'https://github.com/ObsaSiyo/niemify',
  license = 'MIT',
}
dependencies = {
  'lua >= 5.4, < 5.5',
  'dkjson >= 2.8, < 3.0',
  'luaexpat >= 1.5.2, < 2.0',
  'luafilesystem >= 1.8, < 2.0',
}
build = {
  type = 'builtin',
  modules = {
    niemify = 'niemify/init.lua',
    ['niemify.converter'] = 'niemify/converter.lua',
    ['niemify.schema'] = 'niemify/schema.lua',
  },
  install = {
    lua = { ['niemify.exchange-demo'] = 'niemify/exchange-demo.xsd' },
    bin = { niemify = 'bin/niemify' },
  },
}
