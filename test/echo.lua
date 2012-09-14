local sock = require'jet.socket'.sync()
local i = 0
while true do
   local num = math.random(1,9999999)
   sock:send
   {
      id = i,
      method = 'echo',
      params = {num}
   }
   local resp = sock:receive()   
   assert(resp.result[1] == num)
   if (i % 1000) == 0 then
      print(resp.result[1],num,i)
   end
   i = i +1
end
