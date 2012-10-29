
local ev = require'ev'
local loop = ev.Loop.default
local jet = require'jet.peer'.new{loop=loop}
local echo = function(...)
   return {...}
end


local start = function()
   jet:method
   {
      path = 'test/blabla',
      call = echo
   }
   jet:batch(
      function()
         local test_echo = jet:method
         {
            path = 'test/echo',
            call = echo
         }
         jet:method
         {
            path = 'test/echo1',
            call = echo
         }
         jet:method
         {
            path = 'test/echo2',
            call = echo
         }
         local horst_echo_3 = jet:method
         {
            path = 'horst/echo3',
            call = echo
         }

         local horst_echo_2 = jet:method
         {
            path = 'horst/echo2',
            call = echo
         }
         

         local bla = 0
         local bla_state = jet:state
         {
            path = 'popo/bla',
            set = function(value)
               bla = value
               if type(bla) == 'number' then
                  bla = bla + 0.1
                  return bla
               end
            end,
            value = bla
         }

         jet:method
         {
            path = 'test/toggle_echo',
            call = function()
               print('TOGGLE',test_echo)
               if test_echo:is_added() then
                  test_echo:remove({succes=function() print('asd') end,error = function() print('ppp') end})
               else
                  test_echo:add()
               end
               local old = bla_state:value()
               bla_state:value(old+0.3)
            end
         }
      end)
end
local s = ev.Timer.new(start,0.0001)
loop:loop()