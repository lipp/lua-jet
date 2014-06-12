local jutils = require'jet.utils'

local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local tsort = table.sort
local unpack = unpack
local mmin = math.min
local mmax = math.max

local noop = jutils.noop
local is_empty_table = jutils.is_empty_table

-- may create and return a sorter function.
-- the sort function is based on the options.sort entries.
local create_sorter = function(options,notify)
  if not options.sort then
    return nil
  end
  
  local sort
  if (options.sort.byValue == nil and options.sort.byValueField == nil) or options.sort.byPath then
    if options.sort.descending then
      sort = function(a,b)
        return a.path > b.path
      end
    else
      sort = function(a,b)
        return a.path < b.path
      end
    end
  else
    local lt
    local gt
    if options.sort.byValue then
      lt = function(a,b)
        return a < b
      end
      gt = function(a,b)
        return a > b
      end
    elseif options.sort.byValueField then
      local tmp = options.sort.byValueField
      local field_str = pairs(tmp)(tmp)
      local get_field = jutils.access_field(field_str)
      lt = function(a,b)
        return get_field(a) < get_field(b)
      end
      gt = function(a,b)
        return get_field(a) > get_field(b)
      end
    end
    
    -- protected sort
    local psort = function(s,a,b)
      local ok,res = pcall(s,a,b)
      if not ok or not res then
        return false
      else
        return true
      end
    end
    
    if options.sort.descending then
      sort = function(a,b)
        return psort(gt,a.value,b.value)
      end
    else
      sort = function(a,b)
        return psort(lt,a.value,b.value)
      end
    end
  end
  assert(sort)
  
  local from = options.sort.from or 1
  local to = options.sort.to or 10
  local sorted = {}
  local matches = {}
  local index = {}
  local n
  
  local is_in_range = function(i)
    return i and i >= from and i <= to
  end
  
  local initialized
  
  local sorter = function(notification,initializing)
    local event = notification.event
    local path = notification.path
    local value = notification.value
    if initializing then
      if index[path] then
        return
      end
      tinsert(matches,{
          path = path,
          value = value,
      })
      index[path] = #matches
      return
    end
    local last_matches_len = #matches
    local lastindex = index[path]
    if event == 'remove' then
      if lastindex then
        tremove(matches,lastindex)
        index[path] = nil
      else
        return
      end
    elseif lastindex then
      matches[lastindex].value = value
    else
      tinsert(matches,{
          path = path,
          value = value,
      })
    end
    
    tsort(matches,sort)
    
    for i,m in ipairs(matches) do
      index[m.path] = i
    end
    
    if last_matches_len < from and #matches < from then
      return
    end
    
    local newindex = index[path]
    local is_in = is_in_range(newindex)
    
    -- special treatment for states which change
    -- value without changing positions
    if is_in and lastindex and newindex == lastindex then
      notify({
          n = n,
          changes = {
            {
              path = path,
              value = value,
              index = newindex,
            }
          }
      })
      return
    end
    
    local start
    local stop
    local was_in = is_in_range(lastindex)
    
    if is_in and was_in then
      start = mmin(lastindex,newindex)
      stop = mmax(lastindex,newindex)
    elseif is_in and not was_in then
      start = newindex
      stop = mmin(to,#matches)
    elseif not is_in and was_in then
      start = lastindex
      stop = mmin(to,#matches)
    elseif not initialized then
      initialized = true
      start = from
      stop = mmin(to,#matches)
    else
      return
    end
    
    local changes = {}
    for i=start,stop do
      local new = matches[i]
      local old = sorted[i]
      if new and new ~= old then
        tinsert(changes,{
            path = new.path,
            value = new.value,
            index = i,
        })
      end
      sorted[i] = new
      if not new then
        break
      end
    end
    
    local new_n = mmin(to,#matches) - from + 1
    
    if new_n ~= n or #changes > 0 then
      n = new_n
      notify({
          changes = changes,
          n = n,
      })
    end
  end
  
  local flush = function()
    tsort(matches,sort)
    
    for i,m in ipairs(matches) do
      index[m.path] = i
    end
    
    n = 0
    
    local changes = {}
    for i=from,to do
      local new = matches[i]
      if new then
        new.index = i
        n = i - from + 1
        sorted[i] = new
        tinsert(changes,new)
      end
    end
    
    notify({
        changes = changes,
        n = n,
    })
  end
  
  return sorter,flush
end

return {
  new = create_sorter
}
