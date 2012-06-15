local j = require'jet'.new({ip=arg[1]})
j:fetch('',print)
j:loop()
