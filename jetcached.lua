#!/usr/bin/lua
local zmember = require'zbus.member'
local zbus_config = require'zbus.json'
zbus_config.name = 'jet.cached'
local zm = zmember.new(zbus_config)
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

local root = new_node()
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
         return root
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
      local element = root
      local last
      for i=1,#parts do
         local part = parts[i]
         last = element      
         if not is_node(element) then
            local msg = 'url part '..parts[i-1].. '('..tconcat(parts,'.')..') is not a node'
            log(msg)           
            error(server_error(msg))
         end
         element = element[part]
         if not element then
            error(method_not_found(url))	 
         end
      end    
      return element
   end

local on_value_change = 
   function(url,_,val)
      url = remove_method(url)
      local ok,entry = pcall(cache,url)
      if not ok then
         log('error getting cache element',url,entry)
      else	
         entry.value = val
      end     
   end

local on_schema_change = 
   function(url,_,schema)
      url = remove_method(url)
      local ok,entry = pcall(cache,url)
      if not ok then
         log('error getting cache element',url,entry)
      else	
         entry.schema = schema
      end     
   end

local rem = 
   function(_,url,more)
      local parts = {}
      for part in url:gmatch('[^%.]+') do
         tinsert(parts,part)
      end
      if url:find('%.%.') or url:sub(#url) == '.' then
         local msg = 'jetcache invalid url:'..url
         log(msg)
         error(server_error(msg))
      end
      local element = root
      local elements = {}
      local last
      for i=1,#parts-1 do
         local part = parts[i]
         last = element
         if not is_node(element) then
            local msg = 'url part '..parts[i-1].. '('..tconcat(parts,'.')..') is not a node'
            log(msg)           
            error(server_error(msg))
         end
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
         log('rem',url,more)
         zm:notify_more(url..':delete',more,{type=type})
      end
      elements[0] = root
      for i=#elements,1,-1 do
         local el = elements[i]
         if el:empty() then
            elements[i-1][parts[i]] = nil
            elements[i-1]:decrement()
            local url = tconcat(parts,'.',1,i)
            log('rem 2',url,more)
            zm:notify_more(url..':delete',more,{type='node'})
         else
            local url = tconcat(parts,'.',1,i)
         end
      end
   end

local add = 
   function(_,url,description,more)
--      log('jetcache.add',url,more)
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
      local element = root
      local last
      for i=1,#parts do
         local part = parts[i]
         last = element
         if not is_node(element) then
            local msg = 'url part '..parts[i-1].. '('..tconcat(parts,'.')..') is not a node'
            log(msg)           
            error(server_error(msg))
         end
         element = element[part]      
         if i==#parts then
            if element then
               local msg = 'node '..part.. '('..tconcat(parts,'.')..') occupied'
               log(msg,element)
               error(server_error(msg))
            else
               last[part] = description
               last:increment()
--               log('add',url,more)
               zm:notify_more(url..':create',more,description)
            end
         elseif not element then
            last[part] = new_node()
            element = last[part]
            last:increment()
            local new_url = tconcat(parts,'.',1,i)
--            log('add 2',new_url)
            zm:notify_more(new_url..':create',true,{type='node'})
         end
      end
   end

local add_much = 
   function(_,much)
      local added = {}
      local next = pairs(much)
      local url,desc = next(much)
      while url do
         local url2,desc2 = url,desc
         url,desc = next(much,url)
         local ok,err = pcall(add,_,url2,desc2,url)
         if ok then
            tinsert(added,url)
         else
            for _,rem_url in ipairs(added) do
               pcall(rem,_,url)
            end
            error(err)
         end
      end
   end

local rem_much = 
   function(_,url_array)
--      log('remove_much')
      local len = #url_array
      for i,url in ipairs(url_array) do
--         log('DEMY',url,i~=len)
         pcall(rem,_,url,i~=len)
      end
   end


zm:listen_add('^[^:]+:value$',on_value_change)
zm:listen_add('^[^:]+:schema$',on_schema_change)
zm:replier_add('^jet%.add$',add)
zm:replier_add('^jet%.add_much$',add_much)
zm:replier_add('^jet%.rem$',rem)
zm:replier_add('^jet%.rem_much$',rem_much)

zm:replier_add(
   '^.*:list$',
   function(url)
      --    print('cache',root.horst,root.horst and root.horst.name)
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
   '^jet%.fetch$',
   function(_,expr)
--      log('fetch',expr)      
      local matches = {}
      local explore_childs
      
      explore_childs = function(node,prevname)
         for childname,child in pairs(node) do
            local fullname
            if prevname then
               fullname = prevname..'.'..childname
            else
               fullname = childname
            end
            if fullname:match(expr) then
               if is_node(child) then                  
                  tinsert(matches,{name=fullname,type='node'})
               else
                  child.name = fullname
                  tinsert(matches,child)
               end
            end
            if is_node(child) then      
               explore_childs(child,fullname)
            end
         end
      end
      explore_childs(root)
      return matches
   end)
 
zm:replier_add(
   '^.*:get$',
   function(url)
      local property_or_monitor = remove_method(url)
      return cache(property_or_monitor).value
   end)

local daemonize
for _,opt in ipairs(arg) do
   if opt == '-d' or opt == '--daemon' then      
      local ffi = require'ffi'
      if not ffi then
         log('daemonizing failed: ffi (luajit) is required.')
         os.exit(1)
      end
      ffi.cdef'int daemon(int nochdir, int noclose)'
      daemonize = function()
         assert(ffi.C.daemon(1,1)==0)
      end
   end
end
zm:loop{daemonize=daemonize}
