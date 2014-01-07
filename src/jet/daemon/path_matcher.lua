local jutils = require'jet.utils'
local is_empty_table = jutils.is_empty_table
local ipairs = ipairs
local sfind = string.find
local sub = string.sub
local tinsert = table.insert

local contains = function(what)
  return function(path)
    return sfind(path,what,1,true)
  end
end

local contains_all_of = function(what_array)
  return function(path)
    for _,what in ipairs(what_array) do
      if not sfind(path,what,1,true) then
        return false
      end
    end
    return true
  end
end

local contains_one_of = function(what_array)
  return function(path)
    for _,what in ipairs(what_array) do
      if sfind(path,what,1,true) then
        return true
      end
    end
    return false
  end
end

local starts_with = function(what)
  return function(path)
    return sub(path,1,#what) == what
  end
end

local ends_with = function(what)
  return function(path)
    return sub(path,#path-#what+1) == what
  end
end

local equals = function(what)
  return function(path)
    return path == what
  end
end

local equals_one_of = function(what_array)
  return function(path)
    for _,what in ipairs(what_array) do
      if path == what then
        return true
      end
    end
    return false
  end
end

local negate = function(gen)
  return function(...)
    local f = gen(...)
    return function(...)
      return not f(...)
    end
  end
end

-- this variable due to a bug in ludent (indention for lua).
local ends_not_with = negate(ends_with)

local generators = {
  equals = equals,
  equalsNot = negate(equals),
  contains = contains,
  containsNot = negate(contains),
  containsAllOf = contains_all_of,
  containsOneOf = contains_one_of,
  startsWith = starts_with,
  startsNotWith = negate(starts_with),
  endsWith = ends_with,
  endsNotWith = ends_not_with,
  equalsOneOf = equals_one_of,
  equalsNotOneOf = negate(equals_one_of),
}

local predicate_order = {
  'equals',
  'equalsNot',
  'endsWith',
  'startsWith',
  'contains',
  'containsNot',
  'containsAllOf',
  'containsOneOf',
  'startsNotWith',
  'endsNotWith',
  'equalsOneOf',
  'equalsNotOneOf',
}

-- given the fetcher options table, creates a function which performs the path
-- matching stuff.
-- returns nil if no path matching is required.
local create_path_matcher = function(options)
  if not options.path then
    return nil
  end
  
  local po = options.path
  local ci = po.caseInsensitive
  
  local predicates = {}
  
  for _,name in ipairs(predicate_order) do
    local value = po[name]
    if value then
      local gen = generators[name]
      if ci then
        if type(value) == 'table' then
          for i,v in ipairs(value) do
            value[i] = v:lower()
          end
        else
          value = value:lower()
        end
      end
      tinsert(predicates,gen(value))
    end
  end
  
  if ci then
    if #predicates == 1 then
      local pred = predicates[1]
      return function(_,lpath)
        return pred(lpath)
      end
    else
      return function(_,lpath)
        for _,pred in ipairs(predicates) do
          if not pred(lpath) then
            return false
          end
        end
        return true
      end
    end
  else
    if #predicates == 1 then
      local pred = predicates[1]
      return function(path,_)
        return pred(path)
      end
    else
      return function(path,_)
        for _,pred in ipairs(predicates) do
          if not pred(path) then
            return false
          end
        end
        return true
      end
    end
  end
end

return {
  new = create_path_matcher,
}
