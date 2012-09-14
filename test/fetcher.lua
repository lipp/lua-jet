local jet = require'jet.client'.new()
local cjson = require'cjson'
jet:fetch('test_fetch','.*',
          function(params)             
             print('fetching',cjson.encode(params))
          end)

-- jet:fetch('test_fetch2','.*2',
--           function(params)             
--              print('fetching 2',cjson.encode(params))
--           end)

-- jet:fetch('test_fetch 3',{match={'test.*'},unmatch={'.*2'}},
--           function(params)             
--              print('fetching 3',cjson.encode(params))
--           end)
jet:loop()
--loop:loop()