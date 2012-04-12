local jet = require'jet'
local j = jet.new{name='some_service'}
local d = j:domain('test')
local ev = require'ev'

local assign = 
   function(var)
      return function(new_var)
                var = new_var
             end
   end
                  
--local ok, err = pcall(function()
local my_name = 'KLAUS'
d:state{
   name = 'name',
   set = function(new_name)
            if #new_name > 3 and #new_name < 10 then
               my_name = new_name
            else
               error{message='name too long',code=123}
            end
         end,
   value = my_name
}

local hobby = 'dance'
d:state{ 
   name = 'hobby', 
   set = assign(hobby), 
   value = hobby
}

local freq = 100
d:state{
   name = 'analog.filter.freq', 
   set = assign(freq), 
   value = freq
}

local type = 'bessel'
d:state{
   name = 'analog.filter.type',
   set = assign(type),
   value = type
}

local rate = 1000
d:state{
   name = 'analog.sample_rate',
   set = assign(rate),
   value = rate
}

local awe = 1000
d:state{
   name = 'digital.is.great.and.awesome',
   set = assign(awe),
   value = awe
}

local fluid = math.pi
d:state{
   name = 'digital.is.great.and.fluid',
   set = assign(fluid),
   value = fluid
}

local soon = "hallo"
d:state{
   name = 'digital.is.great.and.soon',
   set = assign(soon),
   value = soon
}

local blabla = "aja"
d:state{
   name = 'digital.was.blabla',
   set = assign(blabla),
   value = blabla
}

local num = 12349
d:state{
   name = 'digital.magic',
   set = function(new)
            num = new + 0.1
            return num            
         end,
   value = num
}

local products = {}
d:method{
   name = 'products.create',
   call = function(name) 
             if products[name] then
                error{
                   message = 'product already exists:'..name,
                   code = 123
                }
             end
             products[name] = {}            
             local a = 1
             products[name].a = d:state{
                name = 'products.'..name..'.a',
                set = assign(a),
                value = a
             }
             local b = 2
             products[name].b = d:state{
                name = 'products.'..name..'.b',
                set = assign(b),
                value = b
             }
          end
}

d:method{
   name = 'products.delete',
   call = function(name) 
             if not products[name] then
                error{
                   message = 'product does not exists:'..name,
                   code = 123
                }
             end
             products[name].a:remove()
             products[name].b:remove()
          end
}

d:method{
   name = 'add_numbers',
   call = function(a,b) 
             return a+b
          end,
   schema = {params={{class='double'},{class='double'}},result={class="double"}}
}

local points = 300
j:domain('horst'):state{
   name = 'skat.points',
   set = assign(points),
   value = points
}

local fun = 'big'
j:domain('horst'):state{
   name = 'skat.fun',
   set = assign(fun),
   value = fun
}

local counter_slow = 0
local slow = j:domain('test'):state{
   name = 'counter_slow',
   value = counter_slow
}

local counter_fast = 0
local fast = j:domain('test'):state{
   name = 'counter_fast',
   value = counter_fast
}

--local counter_fast = 0
local fast2 = j:domain('test'):state{
   name = 'once.again.counter_fast',
   value = counter_fast
}


local timer_slow = ev.Timer.new(
   function()
      counter_slow = counter_slow + 1
      slow:change({value=counter_slow})
   end,0.0001,arg[1] or 2)

local rem_slow
rem_slow =
   d:method{
   name = 'remove_counter_slow',
   call = function()
             timer_slow:stop(ev.Loop.default)
             slow:remove()
             rem_slow:remove()
          end
}

local timer_fast = ev.Timer.new(
   function()
      counter_fast = counter_fast + 1
      fast2:change({value=counter_fast},true)
      fast:change({value=counter_fast})
   end,0.0001,arg[2] or 1)

j:loop{ios={timer_slow,timer_fast}}
