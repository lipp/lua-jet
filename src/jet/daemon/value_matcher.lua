local jutils = require'jet.utils'
local tinsert = table.insert

local less_than = function(other)
  return function(x)
    return x < other
  end
end

local greater_than = function(other)
  return function(x)
    return x > other
  end
end

local equals = function(other)
  return function(x)
    return x == other
  end
end

local equals_not = function(other)
  return function(x)
    return x ~= other
  end
end

local generators = {
  lessThan = less_than,
  greaterThan = greater_than,
  equals = equals,
  equalsNot = equals_not,
}

local access_field = jutils.access_field

local is_table = function(tab)
  return type(tab) == 'table'
end

-- given the fetcher options table, creates a function which matches an element (state) value
-- against some defined rule.
local create_value_matcher = function(options)
  if not options.value and not options.valueField then
    return nil
  end
  
  local predicates = {}
  
  if options.value then
    for op,comp in pairs(options.value) do
      local gen = generators[op]
      if gen then
        tinsert(predicates,gen(comp))
      end
    end
  elseif options.valueField then
    for field_str,conf in pairs(options.valueField) do
      local accessor = access_field(field_str)
      local field_predicates = {}
      for op,comp in pairs(conf) do
        local gen = generators[op]
        if gen then
          tinsert(field_predicates,gen(comp))
        end
      end
      local field_pred = function(value)
        if not is_table(value) then
          return false
        end
        local ok,field = pcall(accessor,value)
        if not ok or not field then
          return false
        end
        for _,pred in ipairs(field_predicates) do
          if not pred(field) then
            return false
          end
        end
        return true
      end
      tinsert(predicates,field_pred)
    end
  end
  
  return function(value)
    for _,pred in ipairs(predicates) do
      if not pred(value) then
        return false
      end
    end
    return true
  end
end


return {
  new = create_value_matcher,
  _generators = generators,
  _access_field = access_field,
}
