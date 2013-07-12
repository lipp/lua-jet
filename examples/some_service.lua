#!/usr/bin/env lua
local jet = require'jet.peer'.new({name='some_service'})
local ev = require'ev'

local assign = function(var)
  return function(new_var)
    var = new_var
  end
end

local my_name = 'KLAUS'
jet:state
{
  path = 'name',
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
jet:state
{
  path = 'hobby',
  set = assign(hobby),
  value = hobby
}


local fluid = math.pi
jet:state
{
  path = 'digital/is/great/and/fluid',
  set = assign(fluid),
  value = fluid
}

local num = 12349
jet:state
{
  path = 'digital/magic',
  set = function(new)
    num = new + 0.1
    return num
  end,
  value = num
}


local products = {}
jet:method
{
  path = 'products/create',
  call = function(name)
    if products[name] then
      error{
        message = 'product already exists:'..name,
        code = 123
      }
    end
    products[name] = {}
    local a = 1
    products[name].a = jet:state
    {
      path = 'products/'..name..'/a',
      set = assign(a),
      value = a
    }
    local b = 2
    products[name].b = jet:state
    {
      path = 'products/'..name..'/b',
      set = assign(b),
      value = b
    }
  end
}

jet:method
{
  path = 'products/delete',
  call = function(name)
    if not products[name] then
      error{
        message = 'product does not exists:'..name,
        code = 123
      }
    end
    products[name].a:remove()
    products[name].b:remove()
    products[name] = nil
  end
}


jet:method
{
  path = 'add_numbers',
  call = function(a,b)
    return a+b
  end,
}

jet:method
{
  path = 'sum_numbers',
  call = function(...)
    local args = {...}
    local sum = 0
    for _,v in pairs(args) do
      sum = sum + v
    end
    return sum
  end
}

local peter = {
  age = 35,
  name = 'peter',
}
jet:state
{
  path = 'persons/1232',
  value = peter,
  set = assign(peter)
}

local peters_hobby = 'soccer'
jet:state
{
  path = 'persons/1232/hobby',
  value = peters_hobby,
  set = assign(peters_hobby)
}

local jim = {
  age = 40,
  name = 'jim',
}
jet:state
{
  path = 'persons/1233',
  value = jim,
  set = assign(jim)
}

local jims_hobby = 'guitar'
jet:state
{
  path = 'persons/1233/hobby',
  value = jims_hobby,
  set = assign(jims_hobby)
}

local slow_dude = 5262
jet:state
{
  path = 'slow_dude',
  value = slow_dude,
  set_async = function(reply,value)
    ev.Timer.new(function()
        if value < 10000 then
          slow_dude = value
          reply {
            result = true
          }
        else
          reply {
            error = 'sorry, slow_dude must be < 10000'
          }
        end
      end,1):start(ev.Loop.default)
  end
}

jet:loop()

