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

local is_type = function(typ)
  local lua_type
  if typ == 'object' then
    lua_type = 'table'
  else
    lua_type = typ
  end
  return function(x)
    return type(x) == lua_type
  end
end

local generators = {
  lessThan = less_than,
  greaterThan = greater_than,
  equals = equals,
  equalsNot = equals_not,
  isType = is_type,
}

local access_field = jutils.access_field

local is_table = function(tab)
  return type(tab) == 'table'
end

-- given the fetcher options table, creates a function which matches an element (state) value
-- against some defined rule.
local create_value_matcher = function(options)
  
  -- sorting by value implicit defines value matcher rule against expected type.
  if options.sort then
    if options.sort.byValue then
      -- TODO: check that byValue is either 'number','string','boolean'
      options.value = options.value or {}
      options.value.isType = options.sort.byValue
    elseif options.sort.byValueField then
      local tmp = options.sort.byValueField
      local fieldname,typ = pairs(tmp)(tmp)
      options.valueField = options.valueField or {}
      options.valueField[fieldname] = options.valueField[fieldname] or {}
      options.valueField[fieldname].isType = typ
    end
  end
  
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
      local ok,match = pcall(pred,value)
      if not ok or not match then
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
