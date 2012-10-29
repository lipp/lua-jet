local peer = require'jet.peer'.new()
peer:call('test/toggle_echo')
peer:loop()