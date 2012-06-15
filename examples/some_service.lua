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
                  
local my_name = 'KLAUS'
d:state{
   ['name'] = {
   set = function(new_name)
            if #new_name > 3 and #new_name < 10 then
               my_name = new_name
            else
               error{message='name too long',code=123}
            end
         end,
   value = my_name
}
}

local hobby = 'dance'
d:state{ 
   ['hobby'] = {
   set = assign(hobby), 
   value = hobby
}
}

local fluid = math.pi
d:state{
   ['digital.is.great.and.fluid'] = {
   set = assign(fluid),
   value = fluid
}
}

local num = 12349
d:state{
   ['digital.magic'] = {
   set = function(new)
            num = new + 0.1
            return num            
         end,
   value = num
}
}

local products = {}
d:methods{
   ['products.create'] = {
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
   },
   ['products.delete'] = {
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
}

d:method{
   ['add_numbers'] = {
   call = function(a,b) 
             return a+b
          end,
   schema = {params={{class='double'},{class='double'}},result={class="double"}}
}
}

d:method{
   ['sum_numbers'] = {
   call = function(...) 
             local args = {...}
             local sum = 0
             for _,v in pairs(args) do
                sum = sum + v
             end
             return sum
          end
}
}

local points = 300
j:domain('horst'):state{
   name = 'skat.points',
   set = assign(points),
   value = points
}

local counter_slow = 0
local slow = j:domain('test'):state{
   ['counter_slow'] = {
   value = counter_slow
   }
}

local counter_fast = 0
local fast = j:domain('test'):state{
   ['counter_fast'] = {
   value = counter_fast
   }
}

--local counter_fast = 0
local fast2 = j:domain('test'):state{
   ['once.again.counter_fast'] = {
   value = counter_fast
   }
}


local timer_slow = ev.Timer.new(
   function()
      counter_slow = counter_slow + 1
      slow:change({value=counter_slow})
   end,0.0001,arg[1] or 2)

local rem_slow
rem_slow =
   d:method{
   ['remove_counter_slow'] = {
   call = function()
             timer_slow:stop(ev.Loop.default)
             slow:remove()
             rem_slow:remove()
          end
}
}

local timer_fast = ev.Timer.new(
   function()
      counter_fast = counter_fast + 1
      fast2:change({value=counter_fast},true)
      fast:change({value=counter_fast})
   end,0.0001,arg[2] or 1)

j:loop{ios={timer_slow,timer_fast}}


