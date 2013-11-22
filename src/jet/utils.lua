local noop = function() end
local is_empty_table = function(t)
  return pairs(t)(t) == nil
end

return {
  noop = noop,
  is_empty_table = is_empty_table
}
