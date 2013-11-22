local is_empty_table = require'jet.utils'.is_empty_table

local smatch = string.match

-- determines if the path matcher expression matches exactly one path
local is_exact = function(matcher)
  return matcher:match('^%^([^*]+)%$$')
end

-- determines if the matcher has at least one * wildcard in between other stuff
local is_partial = function(matcher)
  return matcher:match('^%^?%*?([^*]+)%*?%$?$')
end

local sfind = string.find

-- performs a simple (sub) string find (no magics)
local sfind_plain = function(a,b)
  return sfind(a,b,1,true)
end

-- given the fetcher options table, creates a function which performs the path
-- matching stuff.
-- returns nil if no path matching is required.
local create_path_matcher = function(options)
  if not options.match and not options.unmatch and not options.equalsNot then
    return nil
  end
  local ci = options.caseInsensitive
  local unmatch = {}
  local match = {}
  local equals_not = {}
  local equals = {}
  for i,matcher in ipairs(options.match or {}) do
    local exact = is_exact(matcher)
    local partial = is_partial(matcher)
    if exact then
      if ci then
        equals[exact:lower()] = true
      else
        equals[exact] = true
      end
    elseif partial then
      if ci then
        match[partial:lower()] = sfind_plain
      else
        match[partial] = sfind_plain
      end
    else
      if ci then
        match[matcher:lower()] = smatch
      else
        match[matcher] = smatch
      end
    end
  end
  
  for i,unmatcher in ipairs(options.unmatch or {}) do
    local exact = is_exact(unmatcher)
    local partial = is_partial(unmatcher)
    if exact then
      if ci then
        equals_not[exact:lower()] = true
      else
        equals_not[exact] = true
      end
    elseif partial then
      if ci then
        unmatch[partial:lower()] = sfind_plain
      else
        unmatch[partial] = sfind_plain
      end
    else
      if ci then
        unmatch[unmatcher:lower()] = smatch
      else
        unmatch[unmatcher] = smatch
      end
    end
  end
  
  for i,eqnot in ipairs(options.equalsNot or {}) do
    if ci then
      equals_not[eqnot:lower()] = true
    else
      equals_not[eqnot] = true
    end
  end
  
  if is_empty_table(equals_not) then
    equals_not = nil
  end
  
  if is_empty_table(equals) then
    equals = nil
  end
  
  if is_empty_table(match) then
    match = nil
  end
  
  if is_empty_table(unmatch) then
    unmatch = nil
  end
  
  local pairs = pairs
  
  return function(path,lpath)
    if ci then
      path = lpath
    end
    if equals then
      for eq in pairs(equals) do
        if path == eq then
          return true
        end
      end
    end
    if unmatch then
      for unmatch,f in pairs(unmatch) do
        if f(path,unmatch) then
          return false
        end
      end
    end
    if equals_not then
      for eqnot in pairs(equals_not) do
        if eqnot == path then
          return false
        end
      end
    end
    if match then
      for match,f in pairs(match) do
        if f(path,match) then
          return true
        end
      end
    end
    return false
  end
end

return {
  new = create_path_matcher
}
