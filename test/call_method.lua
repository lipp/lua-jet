local ev = require'ev'
local cjson = require'cjson'
local loop = ev.Loop.default
local jet = require'jet.peer'.new
{
   loop = loop
}

local cbs = {
   success = function(result)
      print('RESAULT:',cjson.encode(result))
   end,
   error = function(err)
      print('ERROR:',cjson.encode(err))
   end
}



--jet:call('test/echo2',{'asd',333},cbs)
--jet:call('test/echo2',{'asd',444},cbs)
--jet:call('test/echo2',{'asd',555},cbs)
jet:call('test/echo',{'asd',555})
local dt = 0.001
local tick = 0
ev.Timer.new(function()
                print('TICK',tick)
                tick = tick + 1
                local tick_bak = tick
                jet:batch(function()
                             jet:call('test/echo',{'tock',tick*tick})
                           jet:call('test/echo2',{'asd',tick*tick},{
                                         success = function(result)
                                            assert(result[1] == 'asd')
                                            assert(result[2] == tick_bak*tick_bak)
                                            print('OK')
                                         end})
                             jet:call('test/echo2',{'asd',tick},{
                                         success = function(result)
                                            assert(result[1] == 'asd')
                                            assert(result[2] == tick_bak)
                                            print('OK')
                                         end})
                          end)
             end,dt,dt):start(loop)

jet:io():start(loop)
loop:loop()