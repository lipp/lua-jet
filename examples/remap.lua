#!/usr/bin/env lua
-- remaps another jet state (provided by 'some_servive.lua'
-- asynchronously by fetching the state.
local jet = require'jet.peer'.new{ip=arg[1]}
local cjson = require'cjson'
local remapped
local remap = function(path,event,data)  
   print(path,event,cjson.encode(data))
   if event == 'add' then
      assert(not remapped)
      remapped = jet:state
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
            jet:set('name',new_value,forward)
         end
      }
   elseif event == 'change' then
      remapped:value(data.value)
   end   

end

jet:fetch('^name$',remap)
jet:loop()

