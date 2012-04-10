local jet = require'jet'
local j = jet.new{name='some_service'}
local d = j:domain('test')
local ev = require'ev'

--local ok, err = pcall(function()
local name = 'KLAUS'
d:add_state('name',
	       function(new_name)
		  if #new_name > 3 and #new_name < 10 then
		     name = new_name
		  else
		     error{message='name too long',code=123}
		  end
	       end,name)

local hobby = 'dance'
d:add_state('hobby',
	       function(new_hobby)
		  hobby = new_hobby
	       end,hobby)

local freq = 100
d:add_state('analog.filter.freq',
	       function(new_freq)
		  freq = new_freq
	       end,freq)

local type = 'bessel'
d:add_state('analog.filter.type',
	       function(new)
		  type = new
	       end,type)

local rate = 1000
d:add_state('analog.sample_rate',
	       function(new)
		  rate = new
	       end,rate)

local awe = 1000
d:add_state('digital.is.great.and.awesome',
	       function(new)
		  awe = new
           end,awe)

local fluid = math.pi
d:add_state('digital.is.great.and.fluid',
           function(new)
             fluid = new
           end,fluid)

local soon = "hallo"
d:add_state('digital.is.great.and.soon',
           function(new)
             soon = new
           end,soon)

local blabla = "aja"
d:add_state('digital.was.blabla',
           function(new)
             blabla = new
           end,bllabla)

local num = 12349
d:add_state('digital.magic',
           function(new)
             num = new + 0.1
             return num
           end,num)

d:add_method('delete_prop',
             function(prop) 
               d:remove_state(prop)
               return 
             end
           )

d:add_method('products.create',
             function(prop) 
               local a = 1
               local b = 2
               local c = 3
               d:add_state('products.'..prop..'.a',function(new)
                                                        a = new
                                                      end,a)
               d:add_state('products.'..prop..'.b',function(new)
                                                        b = new
                                                      end,b)
               d:add_state('products.'..prop..'.c',function(new)
                                                        c = new
                                                      end,c)
               return 
             end
           )

d:add_method('products.delete',
             function(product) 
		d:remove_state('products.'..product..'.a')
		d:remove_state('products.'..product..'.b')
		d:remove_state('products.'..product..'.c')
               return 
             end
           )

d:add_method('add_numbers',
             function(a,b) 
		return a+b
             end,
             {params={{class='double'},{class='double'}},result={class="double"}}
           )

local points = 300
j:domain('horst'):add_state('skat.points',
                               function(new) 
                                 points = new 
                               end,points)

local fun = 'big'
j:domain('horst'):add_state('skat.fun',
                               function(new) 
                                 fun = new
                               end,fun)


local counter_slow = 0
local update_counter_slow = j:domain('test'):add_state('counter_slow',counter_slow)

local counter_fast = 0
local update_counter_fast = j:domain('test'):add_state('counter_fast',counter_fast)
local timer_slow = ev.Timer.new(
   function()
      counter_slow = counter_slow + 1
      j:post_state('test.counter_slow',counter_slow)
      j:post_schema('test.counter_slow',{class="int",min=counter_slow})
   end,0.1,arg[1] or 2)

local timer_fast = ev.Timer.new(
   function()
      counter_fast = counter_fast + 1
      j:post_state('test.counter_fast',counter_fast)
   end,0.1,arg[2] or 1)

j:loop{ios={timer_slow,timer_fast}}
-- end)

-- if not ok then
--    print(err.message,err.code,err)
-- end
