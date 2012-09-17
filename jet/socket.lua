local ev = require'ev'
local socket = require'socket'
local cjson = require'cjson'
require'pack' -- blends pack/unpack into string table

local loop = ev.Loop.default
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

module('jet.socket')

local sync = function()
   local sock = socket.connect('localhost',33326)
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
   assert(args.on_close)
   assert(args.on_message)
   assert(args.on_error)
   assert(args.loop)
   -- set non blocking
   sock:settimeout(0)
   -- send message asap
   sock:setoption('tcp-nodelay',true)
   -- enable keep alive for detecting broken connections
   sock:setoption('keepalive',true)   
   local on_message = args.on_message
   local on_close = args.on_close
   local on_error = args.on_error
   local loop = args.loop
   local send_buffer = ''
   local wrapped = {}
   local append = function(message_object)      
      local json_message = cjson.encode(message_object)
--      log('appending',json_message)
      send_buffer = send_buffer..spack('>I',#json_message)..json_message
   end
   local send_message = function(loop,write_io)
      local sent,err,sent_so_far = sock:send(send_buffer,pos)
      if sent then
--         log('sent',#send_buffer,send_buffer:sub(5))
         assert(sent==#send_buffer)
         send_buffer = ''
         write_io:stop(loop)
      elseif err == 'timeout' then                  
         log('sent timeout',pos)                  
         pos = sent_so_far
      elseif err == 'closed' then
         log('sent closed',pos) 
         write_io:stop(loop)
         on_close(wrapped)
      else
         log('sent error',err) 
         write_io:stop(loop)
         on_close(wrapped)           
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
   wrapped.send = function(_,message_object)  
      log(cjson.encode(message_object))
      append(message_object)      
      if not send_io:is_active() then
         log('strting io')
         send_io:start(loop)
      end
   end
   wrapped.close = function()
      sock:shutdown()
      sock:close()
   end
   wrapped.read_io = function()
      local len
      local len_bin
      local json_message
      local _
      local receive_message = function(loop,read_io)
--         print('eee2')
         while true do
            if not len_bin or #len_bin < 4 then
               --         print('eee3')
               local err,sub 
               len_bin,err,sub = sock:receive(4,len_bin)
               --            print(len_bin,err,sub)
               if len_bin then
                  _,len = sunpack(len_bin,'>I')               
                  --            print(#len_bin,len,_)
               elseif err == 'timeout' then
                  len_bin = sub
                  return                                   
               elseif err == 'closed' then
                  read_io:stop(loop)
                  on_close(wrapped)
                  return
               else
                  log('WTF?!',err)
                  read_io:stop(loop)
                  on_error(wrapped,err)
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
               --         print('eee4',len)       
               json_message,err,sub = sock:receive(len,json_message)
               if json_message then    
--                  log('recv',json_message)
                  local ok,message = pcall(cjson.decode,json_message)
                  if ok then                  
                     len = nil
                     len_bin = nil
                     json_message = nil                  
                     on_message(wrapped,message)
                  else                  
                     on_message(wrapped,nil,message)
                  end            
               elseif err == 'timeout' then
                  json_message = sub
                  return
               elseif err == 'closed' then
                  read_io:stop(loop)
                  on_close(wrapped)
                  return
               else
                  read_io:stop(loop)
                  on_error(wrapped,err)
                  return
               end
            end
         end
            --         print('eee5',len)       
      end
      local fd = sock:getfd()
      assert(fd > -1)      
      return ev.IO.new(receive_message,fd,ev.READ)
   end
   return wrapped
end

return {
   wrap = wrap,
   sync = sync
       }

