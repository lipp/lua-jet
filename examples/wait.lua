local jet = require'jet'
local j = jet.new('wait_pop')
print('waiting for popo')

j:require('popo.gut',
       function()
         print('i love popo')
         j:notify_value('horst',3)
         j:unloop()
       end)

j:loop()
                    


