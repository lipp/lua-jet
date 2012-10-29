#!/usr/bin/env lua
-- remaps another jet state from another ip/host/computer 
-- to the local jet bus by
-- asynchronously by fetching the state.
local loop = require'ev'.Loop.default
local peer = require'jet.peer'
local local_jet = peer.new{loop=loop}
local remote_jet = peer.new{loop=loop,ip=arg[1]}
local cjson = require'cjson'
local remapped
local remap = function(notification)  
   print(cjson.encode(notification))
   if notification.event == 'add' then
      assert(not remapped)
      remapped = local_jet:state
      {
         path ='remapped',
         value = notification.data.value,
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
            remote_jet:set('name',new_value,forward)            
         end
      }
   elseif notification.event == 'change' then
      remapped:value(notification.data.value)
   end
end

remote_jet:fetch('^name$',remap)
loop:loop()

