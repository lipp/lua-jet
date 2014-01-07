# Testing persistance feature

For manually "testing" play with this (preferably in different terminals):

```shell
$ jetd.lua
$ lua examples/fetch.lua '{}' 172.19.1.41
$ lua examples/persistant_ticker.lua localhost
$ sudo ifconfig lo down
$ sudo ifconfig lo up
```

The idea is to force connections to be closed by shutting down network interfaces.
Both fetch.lua and persistant_ticker.lua are running with persist option and should
automatically reconnect to jetd.

Better, automated test welcome!!!!