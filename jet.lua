local zmember = require'zbus.member'
local zconfig = require'zbus.json'
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local type = type
local error = error
local print = print
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local log = function(...)
               print('jet module',...)
            end

module('jet')

new = 
   function(config)
      config = config or {}
      local j = {}
      zconfig.name = 'jet.' .. (config.name or 'unknown')
      zconfig.broker = {
         ip = config.ip
      }
      j.zbus = zmember.new(zconfig)    
      j.domains = {}
      j.domain = 
         function(self,domain,exp)
            domain = domain..'.'
            if self.domains[domain] then
               return self.domains[domain]
            end
            if not exp then
               exp = '^'..domain:gsub('%.','%%.')..'.*'
            end
            local d = {}
            local zbus = self.zbus

            -- holds all 'set' callbacks
            d._states = {}
            -- holds all method callbacks
            d._methods = {}
            -- register 'set' method for this domain
            zbus:replier_add(
               exp..':set',
               function(url,val)
                  local delim = url:find(':')
                  local name = url:sub(1,delim-1)
                  local prop = d._states[name]
                  if not prop then
                     error({
                              message = "no such state:"..url,
                              code = 112
                           })
                  end
                  local ok,res,dont_notify = pcall(prop,val)
                  if ok then
                     -- if 'd.states[name]' returned a value, it is treated as 'real' value 
                     val = res or val
                     -- notify all interested zbus / jet clients and the jetcached about the new value
                     if not dont_notify then
                        zbus:notify(name..':value',val)
                     end
                  else
                     -- forward error
                     error(res)
                  end                
               end)

            local set_read_only = 
               function()
                  error({
                           message = 'state is read_only',
                           code = 123
                        })
               end

            -- register call method for this domain
            zbus:replier_add(
               exp..':call',
               function(url,...)
                  local delim = url:find(':')
                  local name = url:sub(1,delim-1)
                  local method = d._methods[name]
                  if not method then
                     error({
                              message = "no such method:" ..url,
                              code = 111
                           })
                  end
                  return method(...)
               end)

            d.state = 
               function(self,descs) 
                  local name,desc = pairs(descs)(descs)
                  local states = self:states{
                     [name] = desc
                  }
                  return states[name]
               end

            d.states = 
               function(self,descs)
                  local states = {}
                  local much = {}
                  for name,desc in pairs(descs) do
                     local setf = desc.set
                     local initial_value = desc.value
                     local fullname = domain..name
                     self._states[fullname] = setf or set_read_only
                     local description = {
                        type = 'state',
                        value = desc.value,
                        schema = desc.schema
                     }
                     if not setf then
                        description.read_only = true
                     end
                     local change = 
                        function(_self_,what,more)
                           local val = what.value
                           local schema = what.schema
                           if val and schema then
                              zbus:notify_more(fullname..':schema',true,schema)
                              zbus:notify_more(fullname..':value',more,val)
                        elseif val then
                           _self_.value = val
                           zbus:notify_more(fullname..':value',more,val)
                        elseif schema then
                           zbus:notify_more(fullname..':schema',more,schema)
                        end
                     end
                     local remove = 
                        function()
                           if not self._states[fullname] then
                              error(fullname..' is not a state of domain '..domain)
                           end
                           zbus:call('jet.rem',fullname)
                           self._states[fullname] = nil
                        end
                     states[name] = {
                        set = setf,
                        value = desc.value,
                        remove = remove,
                        change = change
                     }  
                     much[fullname] = description
                  end
                  zbus:call('jet.add_much',much)                
                  local remove_all = 
                     function()
                        local state_names = {}
                        for name in pairs(states) do
                           tinsert(state_names,domain..name)
                        end
                        zbus:call('jet.rem_much',state_names)                
                     end
                  return states,remove_all
               end

            d.method = 
               function(self,descs) 
                  local name,desc = pairs(descs)(descs)
                  local methods = self:methods{
                     [name] = desc
                  }
                  return methods[name]
               end
            
            d.methods = 
               function(self,descs)
                  local methods = {}
                  local much = {}
                  for name,desc in pairs(descs) do
                     if not desc.call then
                        error('no "call" specified')
                     end
                     local fullname = domain..name
                     self._methods[fullname] = desc.call
                     local description = {
                        type = 'method',
                        schema = desc.schema
                     }
                     local remove = 
                        function()
                           if not self._methods[fullname] then
                              error(fullname..' is not a method of domain '..domain)
                           end
                           zbus:call('jet.rem',fullname)
                           self._methods[fullname] = nil
                        end
                     methods[name] = {
                        remove = remove
                     }
                     much[fullname] = description
                  end
                  zbus:call('jet.add_much',much)
                  local remove_all = 
                     function()
                        local method_names = {}
                        for name in pairs(method) do
                           tinsert(method_names,domain..name)
                        end
                        zbus:call('jet.rem_much',method_names)                
                     end                  
                  return methods,remove_all
               end

            d.remove_all = 
               function(self)
                  pcall(
                     function()
                        -- remove all properties
                        local state_names = {}
                        for name in pairs(self._states) do
                           tinsert(state_names,name)
                        end
                        zbus:call('jet.rem_much',state_names)                
                        self._states = {}
                        --remove all methods
                        local method_names = {}
                        for name in pairs(self._methods) do
                           tinsert(method_names,name)
                        end
                        zbus:call('jet.rem_much',method_names)                
                        self._methods = {}
                     end)
               end
            self.domains[domain] = d
            return d
         end -- domain 

      j.unfetch = function(self,path)
         self.zbus:listen_remove('^'..path)
      end
      
      j.fetch = function(self,expr,f)
         -- to prevent missing events during fetch call,
         -- register listener first. events which occur until
         -- return of this call will be forwarded to this
         -- process and will be queued by the socket
         -- and will be automatically worked off later on.
         -- NOTE: this process is single threaded and this call will
         -- never ever be preempted, so dont worry about f being
         -- called between
         -- HERE
         self.zbus:listen_add('^'..expr,f)
         local matches = self.zbus:call('jet.fetch',expr)            
         for i,match in ipairs(matches) do
            local name = match.name
            match.name = nil
            f(name..':create',i~=#matches,match)
         end
         -- AND HERE
      end

      j.set = 
         function(self,prop,val)
            self.zbus:call(prop..':set',val)
         end

      j.get = 
         function(self,prop)
            return self.zbus:call(prop..':get')
         end

      j.call = 
         function(self,method,...)
            return self.zbus:call(method..':call',...)
         end

      j.list = 
         function(self,node)
            return self.zbus:call(node..':list')
         end

      j.on = 
         function(self,element,event,method)
            if not self.listeners then
               self.listeners = {}
               self.zbus:listen_add(
                  '^.*:'..event,
                  function(url,_,...)
                     local name = url:match('^(.*):'..event..'$')              
                     for _,listener in pairs(self.listeners) do
                        if listener.event==event and name==listener.element then
                           if listener.method(...) == false then
                              self:off(element,event)
                           end
                        end
                     end                         
                  end)
            end
            local listener = {
               element=element,
               event=event,
               method=method
            }
            self.listeners[element..event] = listener
         end

      j.off = 
         function(self,element,event)
            if not self.listeners then
               return
            end   
            self.listeners[element..event] = nil
            if not pairs(self.listeners)(self.listeners) then
               self.zbus:listen_remove('^.*:'..event)
            end
         end    
      
      j.require = 
         function(self,what,f)
            local event = 'create'
            local found = false
            self:on(
               what,event,
               function()
                  if not found then
                     f()
                     return false -- removes listeners
                  end
               end)
            local parts = {}
            for part in what:gmatch('[^.]+') do
               tinsert(parts,part)
            end
            local name = parts[#parts]
            tremove(parts,#parts)
            local parent = tconcat(parts,'.')
            local parent_ok,childs = pcall(self.list,self,parent)
            if parent_ok and childs and childs[name] then
               found = true
               f()
               self:off(what,event)
            end
         end
      
      j.loop = 
         function(self,options)
            self.looping = true
            if not self.unlooped then
               local options = options or {}
               local oexit = options.exit
               options.exit = function()
                  if oexit then
                     oexit()
                  end
                  for _,domain in pairs(self.domains) do
                     domain:remove_all()
                  end
               end
               self.zbus:loop(options)
            end
         end

      j.unloop = 
         function(self)
            self.unlooped = true
            if self.looping then          
               self.zbus:unloop()
            end
         end
      return j 
   end

return {
   new = new
}


