local jpath_matcher = require'jet.daemon.path_matcher'
local jvalue_matcher = require'jet.daemon.value_matcher'

-- creates a fetcher function, eventually combining path and/or value
-- matchers.
-- additionally returns, if the resulting fetcher is case insensitive and thus
-- requires paths to be available as lowercase.
local create_fetcher = function(options,notify)
  local path_matcher = jpath_matcher.new(options)
  local value_matcher = jvalue_matcher.new(options)
  
  local fetchop
  
  if path_matcher and not value_matcher then
    fetchop = function(path,lpath,event,value)
      if not path_matcher(path,lpath) then
        -- return false to indicate NO further interest
        return false
      end
      notify({
          path = path,
          event = event,
          value = value,
      })
      -- return true to indicate further interest
      return true
    end
    
  elseif not path_matcher and value_matcher then
    local added = {}
    fetchop = function(path,lpath,event,value)
      local is_added = added[path]
      if event == 'remove' or not value_matcher(value) then
        if is_added then
          added[path] = nil
          notify({
              path = path,
              event = 'remove',
              value = value,
          })
        end
        -- return false to indicate NO further interest
        return false
      end
      local event
      if not is_added then
        event = 'add'
        added[path] = true
      else
        event = 'change'
      end
      notify({
          path = path,
          event = event,
          value = value,
      })
      -- return true to indicate further interest
      return true
    end
  elseif path_matcher and value_matcher then
    local added = {}
    fetchop = function(path,lpath,event,value)
      if not path_matcher(path,lpath) then
        -- return false to indicate NO further interest
        return false
      end
      local is_added = added[path]
      if event == 'remove' or not value_matcher(value) then
        if is_added then
          added[path] = nil
          notify({
              path = path,
              event = 'remove',
              value = value,
          })
        end
        -- return true to indicate further interest
        return true
      end
      local event
      if not is_added then
        event = 'add'
        added[path] = true
      else
        event = 'change'
      end
      notify({
          path = path,
          event = event,
          value = value,
      })
      -- return true to indicate further interest
      return true
    end
  else
    fetchop = function(path,lpath,event,value)
      notify({
          path = path,
          event = event,
          value = value,
      })
      -- return true to indicate further interest
      return true
    end
  end
  
  local ci = options.path and options.path.caseInsensitive
  
  return fetchop,ci
end

return {
  new = create_fetcher
}
