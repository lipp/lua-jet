local jet = require'jet.peer'.new()
local ev = require'ev'
local loop = ev.Loop.default
local echo = function(self,...)
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
         
         jet:method
         {
            path = 'test/toggle_echo',
            call = function(self)
               print('TOGGLE',test_echo)
               if test_echo:is_added() then
                  test_echo:remove({succes=function() print('asd') end,error = function() print('ppp') end})
               else
                  test_echo:add()
               end
--               horst_echo_2:remove()
--               horst_echo_3:remove()
            end
         }
         local bla = 0
         jet:state
         {
            path = 'popo/bla',
            set = function(self,value)
               bla = value
               if type(bla) == 'number' then
                  bla = bla + 0.1
                  return bla
               end
            end,
            value = bla
         }
      end)
end
local s = ev.Timer.new(start,0.0001)
s:start(loop)
jet:io():start(loop)
loop:loop()