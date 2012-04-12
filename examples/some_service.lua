local jet = require'jet'
local j = jet.new{name='some_service'}
local d = j:domain('test')
local ev = require'ev'

--local ok, err = pcall(function()
local name = 'KLAUS'
d:state('name',
        function(new_name)
           if #new_name > 3 and #new_name < 10 then
              name = new_name
           else
              error{message='name too long',code=123}
           end
        end,name)

local hobby = 'dance'
d:state('hobby',
        function(new_hobby)
           hobby = new_hobby
        end,hobby)

local freq = 100
d:state('analog.filter.freq',
        function(new_freq)
           freq = new_freq
        end,freq)

local type = 'bessel'
d:state('analog.filter.type',
        function(new)
           type = new
        end,type)

local rate = 1000
d:state('analog.sample_rate',
        function(new)
           rate = new
        end,rate)

local awe = 1000
d:state('digital.is.great.and.awesome',
        function(new)
           awe = new
        end,awe)

local fluid = math.pi
d:state('digital.is.great.and.fluid',
        function(new)
           fluid = new
        end,fluid)

local soon = "hallo"
d:state('digital.is.great.and.soon',
        function(new)
           soon = new
        end,soon)

local blabla = "aja"
d:state('digital.was.blabla',
        function(new)
           blabla = new
        end,blabla)

local num = 12349
d:state('digital.magic',
        function(new)
           num = new + 0.1
           return num
        end,num)


local products = {}
d:method('products.create',
         function(name) 
            if products[name] then
               error{
                  message = 'product already exists:'..name,
                  code = 123
               }
            end
            products[name] = {}            
            local a = 1
            products[name].a = d:state('products.'..name..'.a',
                    function(new)
                       a = new
                    end,a)
            local b = 2
            products[name].b = d:state('products.'..name..'.b',
                    function(new)
                       b = new
                    end,b)
            local c = 3
            products[name].c = d:state('products.'..name..'.c',
                    function(new)
                       c = new
                    end,c)
            
         end
      )

d:method('products.delete',
         function(name) 
            if not products[name] then
               error{
                  message = 'product does not exists:'..name,
                  code = 123
               }
            end
            products[name].a:remove()
            products[name].b:remove()
            products[name].c:remove()
         end
      )

d:method('add_numbers',
         function(a,b) 
            return a+b
         end,
         {params={{class='double'},{class='double'}},result={class="double"}}
      )

local points = 300
j:domain('horst'):state('skat.points',
                        function(new) 
                           points = new 
                        end,points)

local fun = 'big'
j:domain('horst'):state('skat.fun',
                        function(new) 
                           fun = new
                        end,fun)


local counter_slow = 0
local slow = j:domain('test'):state('counter_slow',counter_slow)

local counter_fast = 0
local fast = j:domain('test'):state('counter_fast',counter_fast)

--local counter_fast = 0
local fast2 = j:domain('test'):state('once.again.counter_fast',counter_fast)


local timer_slow = ev.Timer.new(
   function()
      counter_slow = counter_slow + 1
      slow:change({value=counter_slow})
   end,0.0001,arg[1] or 2)

local rem_slow
rem_slow =
   d:method('remove_counter_slow',
            function()
               timer_slow:stop(ev.Loop.default)
               slow:remove()
               rem_slow:remove()
            end
         )


local timer_fast = ev.Timer.new(
   function()
      counter_fast = counter_fast + 1
      fast2:change({value=counter_fast},true)
      fast:change({value=counter_fast})
   end,0.0001,arg[2] or 1)

j:loop{ios={timer_slow,timer_fast}}
