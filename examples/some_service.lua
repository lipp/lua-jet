local jet = require'jet'
local j = jet.new()
local d = j:domain('test')
local ev = require'ev'

local name = 'KLAUS'
d:add_property('name','string',
           function(new_name)
             if #new_name > 3 and #new_name < 10 then
               name = new_name
             else
               error{message='name too long',code=123}
             end
           end,name)

local hobby = 'dance'
d:add_property('hobby','string',
           function(new_hobby)
             hobby = new_hobby
           end,hobby)

local freq = 100
d:add_property('analog.filter.freq','float',
           function(new_freq)
             freq = new_freq
           end,freq)

local type = 'bessel'
d:add_property('analog.filter.type','string',
           function(new)
             type = new
           end,type)

local rate = 1000
d:add_property('analog.sample_rate','float',
           function(new)
             rate = new
           end,rate)

local awe = 1000
d:add_property('digital.is.great.and.awesome','float',
           function(new)
             awe = new
           end,awe)

local fluid = math.pi
d:add_property('digital.is.great.and.fluid','float',
           function(new)
             fluid = new
           end,fluid)

local soon = "hallo"
d:add_property('digital.is.great.and.soon','float',
           function(new)
             soon = new
           end,soon)

local blabla = "aja"
d:add_property('digital.was.blabla','float',
           function(new)
             blabla = new
           end,bllabla)

local num = 12349
d:add_property('digital.magic','float',
           function(new)
             num = new + 0.1
             return num
           end,num)

d:add_method('delete_prop','string',
             function(prop) 
               d:remove_property(prop)
               return 
             end
           )

d:add_method('products.create','string',
             function(prop) 
               local a = 1
               local b = 2
               local c = 3
               d:add_property('products.'..prop..'.a','int',function(new)
                                                        a = new
                                                      end,a)
               d:add_property('products.'..prop..'.b','int',function(new)
                                                        b = new
                                                      end,b)
               d:add_property('products.'..prop..'.c','int',function(new)
                                                        c = new
                                                      end,c)
               return 
             end
           )

d:add_method('products.delete','string',
             function(product) 
		d:remove_property('products.'..product..'.a')
		d:remove_property('products.'..product..'.b')
		d:remove_property('products.'..product..'.c')
               return 
             end
           )

d:add_method('add_numbers','',
             function(a,b) 
		return a+b
             end
           )

local points = 300
j:domain('horst'):add_property('skat.points','int',
                               function(new) 
                                 points = new 
                               end,points)

local fun = 'big'
j:domain('horst'):add_property('skat.fun','int',
                               function(new) 
                                 fun = new
                               end,fun)


local counter_slow = 0
local update_counter_slow = j:domain('test'):add_monitor('counter_slow','int'
			      ,counter_slow)

local counter_fast = 0
local update_counter_fast = j:domain('test'):add_monitor('counter_fast','int'
			      ,counter_fast)
local timer_slow = ev.Timer.new(
   function()
      counter_slow = counter_slow + 1
      j:notify_value('test.counter_slow',counter_slow)
   end,0.1,0.1)

local timer_fast = ev.Timer.new(
   function()
      counter_fast = counter_fast + 1
      j:notify_value('test.counter_fast',counter_fast)
   end,0.02,0.02)

j:loop{ios={timer_slow,timer_fast}}




