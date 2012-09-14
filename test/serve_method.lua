local jet = require'jet.client'.new()
local ev = require'ev'
local loop = ev.Loop.default
local echo = function(self,...)
   return {...}
end
local start = function()
jet:add('test/blabla',jet.method{call = echo})
jet:batch(
   function()
      jet:add('test/echo',jet.method{call = echo})
      jet:add('test/echo1',jet.method{call = echo})
      jet:add('test/echo2',jet.method{call = echo})
      jet:add('test/echo3',jet.method{call = echo})
      jet:add('horst/echo2',jet.method{call = echo})
      jet:add('horst/echo3',jet.method{call = echo})
   end)
end
local s = ev.Timer.new(start,0.0001)
s:start(loop)
jet:io():start(loop)
loop:loop()