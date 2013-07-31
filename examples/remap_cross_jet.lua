#!/usr/bin/env lua
-- remaps another jet state from another ip/host/computer
-- to the local jet bus by
-- asynchronously by fetching the state.
local loop = require'ev'.Loop.default
local peer = require'jet.peer'
local local_peer = peer.new{loop=loop}
local remote_peer = peer.new{loop=loop,ip=arg[1]}
local cjson = require'cjson'
local remapped
local remap = function(path,event,data)
  print(path,event,cjson.encode(data))
  if event == 'add' then
    assert(not remapped)
    remapped = local_peer:state
    {
      path ='remapped',
      value = data.value,
      set_async = function(reply,new_value)
        local forward = {
          success = function(res)
            reply
            {
              result = res,
              dont_notify = true
            }
          end,
          error = function(err)
            reply
            {
              error = err
            }
          end
        }
        remote_peer:set('name',new_value,forward)
      end
    }
  elseif event == 'change' then
    remapped:value(data.value)
  end
end

remote_peer:fetch('^name$',remap)
loop:loop()

