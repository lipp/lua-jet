local ev = require'ev'
local socket = require'socket'
local cjson = require'cjson'
require'pack' -- blends pack/unpack into string table

local print = print
local pairs = pairs
local tinsert = table.insert
local tconcat = table.concat
local ipairs = ipairs
local assert = assert
local spack = string.pack
local sunpack = string.unpack
local error = error
local log = print
local pcall = pcall
local type = type

module('jet.socket')

local wrap_sync = function(sock)
   assert(sock)
   local wrapped = {}
   sock:setoption('tcp-nodelay',true)
   wrapped.send = function(_,message_object)
      local json_message = cjson.encode(message_object)
      sock:send(spack('>I',#json_message))
      sock:send(json_message)
   end
   wrapped.receive = function(_)
      local bin_len = sock:receive(4)
      local _,len = bin_len:unpack('>I')
      local json_message = sock:receive(len)
      return cjson.decode(json_message)
   end
   return wrapped
end

local wrap = function(sock,args)
   assert(sock)
   args = args or {}
   -- set non blocking
   sock:settimeout(0)
   -- send message asap
   sock:setoption('tcp-nodelay',true)
   -- enable keep alive for detecting broken connections
   sock:setoption('keepalive',true)   
   local on_message = args.on_message or function() end
   local on_close = args.on_close or function() end
   local on_error = args.on_error or function() end
   local encode = not args.dont_encode
   local decode = not args.dont_decode
   local loop = args.loop or ev.Loop.default
   local send_buffer = ''
   local wrapped = {}
   local send_pos
   local send_message = function(loop,write_io)
      local sent,err,sent_so_far = sock:send(send_buffer,send_pos)
      if sent then
--         log('sent',#send_buffer,send_buffer:sub(5))
         assert(sent==#send_buffer)
         send_buffer = ''
         write_io:stop(loop)
      elseif err == 'timeout' then                  
         log('sent timeout',send_pos)                  
         send_pos = sent_so_far
      elseif err == 'closed' then
--         log('sent closed',pos) 
         write_io:stop(loop)
         on_close(wrapped)
         sock:close()
      else
         log('sent error',err) 
         write_io:stop(loop)
         on_close(wrapped)           
         sock:close()
         log('unknown error:'..err)
      end
   end
   local fd = sock:getfd()
   assert(fd > -1)        
   local send_io = ev.IO.new(send_message,fd,ev.WRITE)
   
   -- sends asynchronous the supplied message object
   --
   -- the message format is 32bit big endian integer
   -- denoting the size of the JSON following   
   wrapped.send = function(_,message)  
--      log('sending',cjson.encode(message))
      if encode then
         message = cjson.encode(message)      
      end
--      assert(cjson.decode(message) ~= cjson.null)
      send_buffer = send_buffer..spack('>I',#message)..message
      send_pos = 0
      if not send_io:is_active() then
--         log('strting io')
         send_io:start(loop)
      end
   end
   wrapped.close = function()
      wrapped.read_io():stop(loop)
      send_io:stop(loop)
      sock:shutdown()
      sock:close()
   end
   wrapped.on_message = function(_,f)
      assert(type(f) == 'function')
      on_message = f
   end
   wrapped.on_close = function(_,f)
      assert(type(f) == 'function')
      on_close = f
   end
   wrapped.on_error = function(_,f)
      assert(type(f) == 'function')
      on_error = f
   end
   local read_io
   wrapped.read_io = function()
      if not read_io then
         local len
         local len_bin
         local json_message
         local _
         local receive_message = function(loop,read_io)
            while true do
               if not len_bin or #len_bin < 4 then
                  local err,sub 
                  len_bin,err,sub = sock:receive(4,len_bin)
                  if len_bin then
                     _,len = sunpack(len_bin,'>I')               
                  elseif err == 'timeout' then
                     len_bin = sub
                     return                                   
                  elseif err == 'closed' then
                     read_io:stop(loop)
                     on_close(wrapped)
                     sock:close()
                     return
                  else
                     log('WTF?!',err)
                     read_io:stop(loop)
                     on_error(wrapped,err)
                     sock:close()
                  end         
               end
               if len then 
                  if len > 1000000 then
                     local err = 'message too big:'..len..'bytes'
                     print('jet.socket error',err)
                     on_error(wrapped,err)
                     read_io:stop(loop)
                     sock:close()
                     return
                  end
                  json_message,err,sub = sock:receive(len,json_message)
                  if json_message then    
                     --                  log('recv',len,json_message)
                     if decode then
                        local ok,message = pcall(cjson.decode,json_message)
                        if ok then                  
                           on_message(wrapped,message)
                        else                  
                           on_message(wrapped,nil,message)
                        end
                     else
                        on_message(wrapped,json_message)
                     end
                     len = nil
                     len_bin = nil
                     json_message = nil                  
                  elseif err == 'timeout' then
                     json_message = sub
                     return
                  elseif err == 'closed' then
                     read_io:stop(loop)
                     on_close(wrapped)
                     sock:close()
                     return
                  else
                     read_io:stop(loop)
                     on_error(wrapped,err)
                     sock:close()
                     return
                  end
               end
            end
         end
         local fd = sock:getfd()
         assert(fd > -1)      
         read_io = ev.IO.new(receive_message,fd,ev.READ)
      end
      return read_io
   end
   return wrapped
end

local mod = {
   wrap = wrap,
   wrap_sync = wrap_sync
}

return mod

