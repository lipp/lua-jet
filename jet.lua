local zbus = require'zbus'
local zconfig = require'zbus.json'
local pcall = pcall
local pairs = pairs
local setmetatable = setmetatable
local type = type
local error = error
local print = print
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat

module('jet')

local new_jet = 
  function(name)
    local j = {}
    zconfig.name = 'jet.' .. (name or 'unknown')
    j.zbus = zbus.member(zconfig)    
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
        d.properties = {}
        -- holds all method callbacks
        d.methods = {}
	-- holds all monitors (just their names as key)
	d.monitors = {}
        -- register 'set' method for this domain
        zbus:replier_add(
          exp..':set',
          function(url,val)
            local delim = url:find(':')
            local name = url:sub(1,delim-1)
            local prop = d.properties[name]
            if not prop then
              error({
                      message = "no such property:"..url,
                      code = 112
                    })
            end
            local ok,res = pcall(prop,val)
            if ok then
              -- if 'd.properties[name]' returned a value, it is treated as 'real' value 
              val = res or val
              -- notify all interested zbus / jet clients and the jetcached about the new value
              zbus:notify(name..':value',val)
            else
              -- forward error
              error(res)
            end                
          end)

        -- register call method for this domain
        zbus:replier_add(
          exp..':call',
          function(url,...)
            local delim = url:find(':')
            local name = url:sub(1,delim-1)
            local method = d.methods[name]
            if not method then
              error({
                      message = "no such method:" ..url,
                      code = 111
                    })
            end
            return method(...)
          end)

        --- add a property.
        -- jetcached holds copies of the properties' values and updates them on ':value' notification.
        -- @param schema introspection of the property (i.e. min, max)
        -- @param setf callback funrction for setting the property.
        d.add_property = 
          function(self,name,setf,initial_value,schema)
            local fullname = domain..name
            self.properties[fullname] = setf
	    local description = {
	       type = 'property',
	       value = initial_value,
	       schema = schema
	    }
            zbus:call('jet.add',fullname,description)
	    return function(new_val)
		      zbus:call(fullname..':update',new_val)
		   end
          end

        d.remove_property = 
          function(self,name)
            local fullname = domain..name
	     if not self.properties[fullname] then
		error(fullname..' is not a property of domain '..domain)
	     end
	     zbus:call('jet.rem',fullname)
	     self.properties[fullname] = nil
	 end

        d.add_monitor = 
          function(self,name,initial_value,schema)
            local fullname = domain..name
	     self.monitors[fullname] = true
	     local description = {
		type = 'monitor',
		value = initial_value,
		schema = schema
	     }
	     zbus:call('jet.add',fullname,description)
	    return function(new_val)
		      zbus:call(fullname..':update',new_val)
		   end
	 end

        d.remove_monitor = 
          function(self,name)
            local fullname = domain..name
	     if not self.monitors[fullname] then
		error(fullname..' is not a monitor of domain '..domain)
	     end
            zbus:call('jet.rem',fullname)
	    self.monitors[fullname] = nil
	 end

       d.notify_value = 
	  function(self,name,value)
	     local fullname = domain..name
	     zbus:call(fullname..':update',value)
	  end
       

        d.add_method = 
          function(self,name,f,schema)
            local fullname = domain..name
            self.methods[fullname] = f
	    local description = {
	       type = 'method',
	       schema = schema
	    }
            zbus:call('jet.add',fullname,'method',description)
          end

        d.remove_method = 
          function(self,name)
            local fullname = domain..name
	     if not self.methods[fullname] then
		error(fullname..' is not a method of domain '..domain)
	     end
            zbus:call('jet.rem',fullname)
            self.properties[fullname] = nil
          end

        d.cleanup = 
          function(self)
            pcall(
              function()
                -- remove all properties
                for prop in pairs(self.properties) do
                  zbus:call('jet.rem',prop)
	       end
	       self.properties = {}
                --remove all methods
                for method in pairs(self.methods) do
                  zbus:call('jet.rem',method)
	       end
	       self.methods = {}
	       -- remove all monitors
                for monitor in pairs(self.monitors) do
                  zbus:call('jet.rem',monitor)
	       end
	       self.monitors = {}
              end)
          end
        self.domains[domain] = d
        return d
      end -- domain 

    j.set_property = 
      function(self,prop,val)
        self.zbus:call(prop..':set',val)
      end

    j.get_property = 
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

    j.notify_value = 
      function(self,node,value)
        self.zbus:notify(node..':value',value)
      end

    j.on = 
      function(self,element,event,method)
        if not self.listeners then
          self.listeners = {}
          self.zbus:listen_add(
            '^.*:'..event,
            function(url,...)
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
          self.zbus:loop{
            exit = function()
                     if options.exit then
                       options.exit()
                     end
                     for _,domain in pairs(self.domains) do
                       domain:cleanup()
                     end
                   end,
            ios = options.ios or {}
          }
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

new = new_jet
return {
  new = new
}


