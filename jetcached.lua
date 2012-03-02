#!/usr/bin/env lua
local zbus = require'zbus'
local zbus_config = require'zbus.json'
zbus_config.name = 'jet.cached'
local m = zbus.member(zbus_config)
local cjson = require'cjson'
local tinsert = table.insert
local tconcat = table.concat
local assert = assert
local error = error

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
    if not url and #url == 0 then
      return _cache
    end
    local parts = {}
    for part in url:gmatch('[^%.]+') do
      tinsert(parts,part)
    end
    if url:find('%.%.') or url:sub(#url) == '.' then
      local msg = 'jetcache invalid url:'..url
      print(msg)
      error({message=msg,code=123})
    end
    local element = _cache
    local last
    for i=1,#parts do
      local part = parts[i]
      last = element
      element = element[part]
    end    
    return element
  end

local update = 
  function(url,val)
    local entry = cache(url)
    if entry then
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
      print(msg)
      error({message=msg,code=123})
    end
    local element = _cache
    local elements = {}
    local last
    for i=1,#parts-1 do
      local part = parts[i]
      last = element
      element = element[part]
      if not element then
	 print('invalid path'..url)
        error('invalid path '..url)
      end
      tinsert(elements,element)      
    end
    if element[parts[#parts]] then
      local type = element[parts[#parts]].type
      element[parts[#parts]] = nil
      element:decrement()
      print('rem',url)
      m:notify(url..':delete',{type=type})
    end
    elements[0] = _cache
    for i=#elements,1,-1 do
      local el = elements[i]
--      print(tconcat(parts,'.',1,i),el:count())
      if el:empty() then
        elements[i-1][parts[i]] = nil
        elements[i-1]:decrement()
        local url = tconcat(parts,'.',1,i)
        print('rem',url)
        m:notify(url..':delete',{type='node'})
      else
        local url = tconcat(parts,'.',1,i)
      end
    end
  end

local add = 
  function(_,url,type,value,schema)
    local parts = {}
    for part in url:gmatch('[^%.]+') do
      tinsert(parts,part)
    end
    if url:find('%.%.') or url:sub(#url) == '.' then
      local msg = 'jetcache invalid url:'..url
      print(msg)
      error({message=msg,code=123})
    end
    local element = _cache
    local last
    for i=1,#parts do
      local part = parts[i]
      last = element
      element = element[part]      
      if i==#parts then
        if element then
	   print('node occupied',part,tconcat(parts,'.'))
          error('node occupied')
       else
	  local desc = {
	     value = value,
	     schema = schema,
	     type = type
	  }	  
          last[part] = desc
          last:increment()
          print('add',url)
          m:notify(url..':create',desc)
        end
      elseif not element then 
        last[part] = new_node()        
        element = last[part]        
        last:increment()
        local new_url = tconcat(parts,'.',1,i)        
        m:notify(new_url..':create',{type='node'})
        print('add',new_url,parts[i-1],last:count())
      end
    end
  end

m:listen_add('^[^:]+:value$',update)
m:replier_add('^jet.add$',add)
m:replier_add('^jet.rem$',rem)

m:replier_add(
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

m:replier_add(
  '^.*:get$',
  function(url)
    local property_or_monitor = remove_method(url)
    return cache(property_or_monitor).value
  end)

m:loop()
