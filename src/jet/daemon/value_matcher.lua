local ops = {
  lessThan = function(a,b)
    return a < b
  end,
  greaterThan = function(a,b)
    return a > b
  end,
  equals = function(a,b)
    return a == b
  end,
  equalsNot = function(a,b)
    return a ~= b
  end
}


-- given the fetcher options table, creates a function which matches an element (state) value
-- against some defined rule.
local create_value_matcher = function(options)
  if options.where ~= nil then
    if #options.where > 1 then
      return function(value)
        local is_table = type(value) == 'table'
        for _,where in ipairs(options.where) do
          local need_table = where.prop and where.prop ~= '' and where.prop ~= jnull
          if need_table and not is_table then
            return false
          end
          local op = ops[where.op]
          local comp
          if need_table then
            comp = value[where.prop]
          else
            comp = value
          end
          local ok,comp_ok = pcall(op,comp,where.value)
          if not ok or not comp_ok then
            return false
          end
        end
        return true
      end
    elseif options.where then
      if #options.where == 1 then
        options.where = options.where[1]
      end
      local where = options.where
      local op = ops[where.op]
      local ref = where.value
      if not where.prop or where.prop == '' or where.prop == jnull then
        return function(value)
          local is_table = type(value) == 'table'
          if is_table then
            return false
          end
          local ok,comp_ok = pcall(op,value,ref)
          if not ok or not comp_ok then
            return false
          end
          return true
        end
      else
        return function(value)
          local is_table = type(value) == 'table'
          if not is_table then
            return false
          end
          local ok,comp_ok = pcall(op,value[where.prop],ref)
          if not ok or not comp_ok then
            return false
          end
          return true
        end
      end
    end
  end
  return nil
end

return {
  new = create_value_matcher
}
