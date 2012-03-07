#!/usr/bin/env lua
local zbus = require'zbus'
local zbus_config = require'zbus.json'
zbus_config.name = 'jet.cached'
local zm = zbus.member(zbus_config)
local tinsert = table.insert
local tconcat = table.concat
local assert = assert
local error = error
local log = 
   function(...)
      print('jetcached',...)
   end

local method_not_found = 
   function(arg,info)
      return {
	 code = -32601,
	 message = 'Method not found',
	 data = {
	    arg = arg,
	    info = info
	 }
      }
   end

local server_error = 
   function(arg,info)
      return {
	 code = -32000,
	 message = 'Server error',
	 data = {
	    arg = arg,
	    info = info
	 }
      }
   end

local new_node = 
  function()
    local n = 0
    return setmetatable(
      {},{
        __index = {
          increment = 
	      function()
		 assert(n >= 0)
		 n = n + 1
	      end,
          decrement = 
	      function()
                        n = n - 1
		 assert(n >= 0)
	      end,
          empty = 
	      function()
		 return n == 0
	      end,
          count = 
	      function()
		 return n
	      end
        }
      })
  end

local _cache = new_node()
local is_node = 
  function(candidate)
    return getmetatable(candidate) ~= nil
  end

local remove_method = 
  function(url)
    return url:sub(1,url:find(':')-1)
  end

local cache = 
  function(url)
    if not url or #url==0 then
      return _cache
    end
    local parts = {}
    for part in url:gmatch('[^%.]+') do
      tinsert(parts,part)
   end
    if url:find('%.%.') or url:sub(#url) == '.' then
      local msg = 'jetcache invalid url:'..url
      log(msg)
      error(method_not_found(url,msg))
    end
    local element = _cache
    local last
    for i=1,#parts do
      local part = parts[i]
      last = element      
      element = element[part]
      if not element then
	 error(method_not_found(url))	 
      end
    end    
    return element
  end

local update = 
  function(url,_,val)
     url = remove_method(url)
     local ok,entry = pcall(cache,url)
     if not ok then
	log('error getting cache element',url,entry)
     else	
	entry.value = val
     end     
  end

local rem = 
  function(_,url)
    local parts = {}
    for part in url:gmatch('[^%.]+') do
      tinsert(parts,part)
    end
    if url:find('%.%.') or url:sub(#url) == '.' then
      local msg = 'jetcache invalid url:'..url
      log(msg)
      error(server_error(msg))
    end
    local element = _cache
    local elements = {}
    local last
    for i=1,#parts-1 do
      local part = parts[i]
      last = element
      element = element[part]
      if not element then
	 log('invalid path'..url)
	 error(server_error('invalid path '..url))
      end
      tinsert(elements,element)      
    end
    if element[parts[#parts]] then
      local type = element[parts[#parts]].type
      element[parts[#parts]] = nil
      element:decrement()
      log('rem',url)
      zm:notify(url..':delete',{type=type})
    end
    elements[0] = _cache
    for i=#elements,1,-1 do
      local el = elements[i]
      if el:empty() then
        elements[i-1][parts[i]] = nil
        elements[i-1]:decrement()
        local url = tconcat(parts,'.',1,i)
        log('rem',url)
        zm:notify(url..':delete',{type='node'})
      else
        local url = tconcat(parts,'.',1,i)
      end
    end
  end

local add = 
  function(_,url,description)
    local parts = {}
    description = description or {}
    for part in url:gmatch('[^%.]+') do
      tinsert(parts,part)
    end
    if url:find('%.%.') or url:sub(#url) == '.' then
      local msg = 'jetcache invalid url:'..url
      log(msg)
      error(server_error(msg))
    end
    local element = _cache
    local last
    for i=1,#parts do
      local part = parts[i]
      last = element
      element = element[part]      
      if i==#parts then
        if element then
	   log('node occupied',part,tconcat(parts,'.'))
	   error(server_error('node occupied'))
       else
          last[part] = description
          last:increment()
          log('add',url)
          zm:notify_more(url..':create',false,description)
        end
      elseif not element then 
        last[part] = new_node()        
        element = last[part]        
        last:increment()
        local new_url = tconcat(parts,'.',1,i)        
        zm:notify_more(new_url..':create',true,{type='node'})
        log('add',new_url,parts[i-1],last:count())
      end
    end
  end

zm:listen_add('^[^:]+:value$',update)
zm:replier_add('^jet%.add$',add)
zm:replier_add('^jet%.rem$',rem)

zm:replier_add(
  '^.*:list$',
  function(url)
    --    print('cache',_cache.horst,_cache.horst and _cache.horst.name)
    local name = remove_method(url)
    local element = cache(name)
    if not is_node(element) then      
      return element
    else
      local list = {}
      for name,child in pairs(element) do
        if is_node(child) then
          list[name] = {type='node'}
        else
          list[name] = child
        end      
      end
      return list
    end
  end)

zm:replier_add(
  '^.*:get$',
  function(url)
    local property_or_monitor = remove_method(url)
    return cache(property_or_monitor).value
  end)

zm:loop()
