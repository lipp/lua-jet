local noop = function() end

local is_empty_table = function(t)
  return pairs(t)(t) == nil
end

--- creates and returns an error table conforming to
-- JSON-RPC Invalid params.
local invalid_params = function(data)
  local err = {
    code = -32602,
    message = 'Invalid params',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Response Timeout.
local response_timeout = function(data)
  local err = {
    code = -32001,
    message = 'Response Timeout',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Internal Error.
local internal_error = function(data)
  local err = {
    code = -32603,
    message = 'Internal error',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Parse Error.
local parse_error = function(data)
  local err = {
    code = -32700,
    message = 'Parse error',
    data = data,
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Method not Found.
local method_not_found = function(method)
  local err = {
    code = -32601,
    message = 'Method not found',
    data = method
  }
  return err
end

--- creates and returns an error table conforming to
-- JSON-RPC Invalid request.
local invalid_request = function(data)
  local err = {
    code = -32600,
    message = 'Invalid Request',
    data = data
  }
  return err
end

-- creates and returns a function, that extracts
-- a (sub) table entry specified by field_str.
-- field_str can be any valid Javascript Object index:
-- "age"
-- "person.age"
-- "person.age.year"
-- "person.friends[0]"
-- passed in a table instance, extracts the field:
-- local accessor = access_field('a.b.c')
-- accessor(some_table)
-- may throw if trying to index non tables.
local access_field = function(field_str)
  if field_str:sub(1,1) ~= '[' then
    field_str = "."..field_str
  end
  local func_str = 'return function(tab) return tab'..field_str..' end'
  return loadstring(func_str)()
end

-- deep table comparison from here:
-- http://snippets.luacode.org/snippets/Deep_Comparison_of_Two_Values_3
--
local equals_deep -- needed as upvalue for recursion
equals_deep = function(t1,t2)
  local ty1 = type(t1)
  local ty2 = type(t2)
  if ty1 ~= ty2 then
    return false
  end
  -- non-table types can be directly compared
  if ty1 ~= 'table' and ty2 ~= 'table' then
    return t1 == t2
  end
  for k1,v1 in pairs(t1) do
    local v2 = t2[k1]
    if v2 == nil or not equals_deep(v1,v2) then
      return false
    end
  end
  for k2,v2 in pairs(t2) do
    local v1 = t1[k2]
    if v1 == nil or not equals_deep(v1,v2) then
      return false
    end
  end
  return true
end

local mapper = function(field_str_map)
  local accessors = {}
  for field_str,name in pairs(field_str_map) do
    accessors[name] = access_field(field_str)
  end
  return function(tab)
    local mapped = {}
    for name,accessor in pairs(accessors) do
      mapped[name] = accessor(tab)
    end
    return mapped
  end
end

return {
  noop = noop,
  is_empty_table = is_empty_table,
  internal_error = internal_error,
  invalid_request = invalid_request,
  invalid_params = invalid_params,
  method_not_found = method_not_found,
  parse_error = parse_error,
  response_timeout = response_timeout,
  access_field = access_field,
  equals_deep = equals_deep,
  mapper = mapper,
}

