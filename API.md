# Jet module API doc.

## jet.peer

To access the `jet.peer` module:

```lua
local peer = require('jet.peer')
```

### pi = peer.new([config])

Creates a new peer using Jet's "trivial" message protocol and returns it.
If `config.sync` is not `true` then all methods of `pi` are async/non-blocking.

```lua
local peer = require('jet.peer')
local pi = peer.new()
```

The `config` table is optional. If provided all entries are optional too:

```lua
local pi = peer.new({
  ip = '192.168.1.23', -- the jet daemon ip, default 'localhost'
  port = '192.168.1.23', -- the jet daemon 'trivial' port, default 11122,
  url = 'ws://jet.nodejitsu.com:80', -- use websocket socket transport with this (websocket) url
  name = 'foo', -- some name which will be assoc. at the daemon for debugging
  loop = my_loop, -- an lua-ev loop instance, default ev.Loop.default
  on_connect = print, -- a function which will be called 'on connect' to the daemon
  on_close = print, -- a function which will be called when the peer closes
  sync = false, -- creates sync working peer
})

-- connect to the public Jet hosted at nodejitsu
local pi_nodejitsu = peer.new({
  url = 'ws://jet.nodejitsu.com:80'
})

-- connect to the local (default) daemon
local pi_local = peer.new()
```

The `url` option overwrites the `ip` and `port` options.
When the `config.sync` flag is set, the peer instance behaves very different than the 'default/async' one.
The 'sync' peer is documented separately.

### pi:close()

Closes the peer instance. All states, methods and fetchers will be removed from the Jet daemon.

### pi:call(path,[params],[callbacks])

Issues a 'call' Jet message to the daemon with the specified path and parameters. If `callbacks` is provided, the message is a Request and either `callbacks.success` or `callbacks.error` will be called on Response.

```lua
pi:call('persons/create',{name='peter',age=23},{
  success = function(result)
    print('success',result)
  end,
  error = function(err)
    print('failure',err.message,err.code)
  end
})
```

### pi:set(path,value,[callbacks])

Issues a 'set' Jet message to the daemon with the specified path and value. If `callbacks` is provided, the message is a Request and either `callbacks.success` or `callbacks.error` will be called on Response.

```lua
pi:set('persons/ae62a',{name='peter',age=33},{
  success = function()
    print('success')
  end,
  error = function(err)
    print('failure',err.message,err.code)
  end
})
```

### fetcher = pi:fetch(contains|fetch_params,fetch_callback,[callbacks])

Creates a new fetcher. If the first parameter is a string, a 'fetch' message whith the following `fetch_params` is send to the daemon:

```lua
fetch_params = {
  path = {
    contains = contains
  }
}
```

Else the `fetch_params` are used unmodified. If `fetch_params.sort` is not defined or is no valid sort option, the `fetch_callback` receives the parameters `(event,path,value,fetcher)`. The `event` can be either `add`, `change` or `remove`. `add` is always the first event. `change` means that the paths's associated `value` has changed and `remove` means that the state or method are not available at the Jet bus any longer. States and methods may become available any time later on, though. Note that `value` is `nil` for methods.

```lua
local allstuff = pi:fetch('.*',function(event,path,value)
  print(event,path,value)
end)
```

Else, if `fetch_params.sort` specifies a valid sort config, the `fetch_callback` receives the parameters `(changes,n)`. To minimize network traffic, only the changes are posted to the peers. `changes` is an array, which contains all entries within the requested sort range (`from`,`to`) which have been changed, added or moved. In addition to their respective `path` and `value` there is also the `index` field, specifying the position within the sort range. `n` denotes the number of elements that are currently in the requested sorted collection. `n` >= 0 and n <= (`to` - `from`).

```lua
local top_ten = {}

local show_top_ten = function(changes,n)
  -- merge the changes into top_ten
  for _,change in ipairs(changes) do
    top_ten[change.index] = {
		path = change.path,
		value = change.value
	}
  end
  -- display top_ten
  -- note: maybe there are only 5 players available (some may lhave left the game meanwhile)
  -- in this case n is 5.
  for i=1,n do
    print('pos:',i,top_ten[i].path,top_ten[i].value)
  end
end

pi:fetch({
    path = {
		startsWith = 'player'
	},
	sort = {
	  byValueField = {
		  score = 'number',
	  }
	  descending = true, -- optional, default is false
	  from = 1, -- optional, default is 1
	  to = 10, -- optional, default is 10
	}
  },function(changes,n)
    print(changes,n)
  end)
```

The `fetcher` argument passed in as `fetch_callback` param is the same as returned by the `pi:fetch(...)` call. You can use the `fetcher` to call `fetcher:unfetch()`.

```lua
-- print first 5 events
local i = 0
pi:fetch('.*',function(event,path,value,fetcher)
  print(event,path,value)
  i = i + 1
  if i == 5 then
    fetcher:unfetch()
  end
end)
```

```lua
-- fetches all available jet states and methods and prints
-- the basic notification info until 'toggle_the_fetch' is called
local print_fetch = pi:fetch(exp,function(path,event,data)
    print(path,event,data)
  end)

pi:method({
    path = 'toggle_the_fetch',
    call = function()
      if print_fetch:is_fetching() then
        print_fetch:unfetch()
        return 'off'
      else
        print_fetch:fetch()
        return 'on'
      end
    end
})
```


### state = pi:state(desc,[callbacks])

Adds a new state to the daemon and returns a `state` instance.
The `callbacks` table is optional. The `desc` parameter must look like this:

```lua
local net_state = pi:state({
  path = 'settings/net', -- a string, required
  value = {             -- any lua value
    mode = 'static'
    address = '182.167.233',
	subnet = '255.255.255.0'
  },
  set = change_net      -- a function which gets called, whenever the peer receives a 'set' Message, optional
  -- set_async = change_net_async -- a function which gets called, whenever the peer receives a 'set' Message, optional
},{
  success = print,      -- a function which gets called when adding the states to the daemon succeeded
  error = print         -- a function which gets called when adding the states to the daemon failed
})
```

If the `path` is already in use by any peer, the error callback is called. The `set` and `set_async` callbacks must ot be defined at the same time for one state. If the `set` and `set_async` callback are not set, the state is considered read-only.

#### set

If the `set` callback is set, it gets called with the requested value:

```lua
local change_net = function(requested_net)
  ... -- process params
end
```

If `change_net` does not return a value and does not throw an error, `requested_net` is considered the new value of the state and a `change` notification is posted to the daemon automatically.

```lua
local change_net = function(requested_net)
  ... -- process params
  ... -- adjust the requested value
  var adjusted = {
    address = requested_net.address,
    mode = requested_net.mode,
	subnet = '255.255.0.0'
  }
  return requested_net
end
```

If `change_net` returns a value, this would be considered the new value of the state and a `change` notification with this value would be posted to the daemon automatically.

```lua
local change_net = function(requested_net)
  ... -- process params
  ... -- some other dude will "manually" issue a state change notification
  return nil,true
end
```

If `change_net` returns `true` at second position, the `set` operation is considered a success BUT no change notification will be posted automatically. Instead some other "dude" must do it, e.g. in this case through `net:value({...})`.

#### set_async

If the `set_async` callback is set, it gets called with a reply function and the requested value:

```lua
local change_net_async = function(reply,requested_net)
  ... -- process params
  on_settings_changed(function(err,ok) -- this is some async action
    if err or not ok then
	  reply({   -- reply with error
	    error = err or 'failure'
	  })
    else
	  reply({   -- reply with result, result value must be not nil and not false
	    result = ok
      })
    end
  end)
end
```

### pi:loop()

Starts the event loop. This call only returns if the `pi` gets closed for some reason. (Internally just calls lua-ev `loop:loop()).
If integrating with other lua-ev watchers, this may not need to be called.

## fetcher

Fetcher can be create by a peer instance (`pi:fetch(...)`).

### fetcher:unfetch([callbacks])

Sends a 'unfetch' Jet message to the daemon. No more notifications are send to the peer.

### fetcher:fetch([callbacks])

Sends a 'fetch' Jet message to the daemon. Notifications will be send again to the peer. This is shorthand for creating the same fetcher again with `pi:fetch(...)`.

### fetcher:is_fetching([callbacks])

Returns true if the fetch is currently active/fetching.

## state

States can be created by a peer instance (`pi:state(...)`).

### state:remove([callbacks])

Removes the state from the jet daemon. The state's `set` or `set_async` callbacks will not be called any more.
The `callbacks` argument is optional.

```lua
net:remove({
  success = print, -- called when the state has been successfully removed from the daemon
  error = print -- callled when the state could be removed from the daemon
})
```

### state:add([value],[callbacks])

Once removed, re-adds the state to the jet daemon. The state's `set` or `set_async` callbacks will be called again.
The `value` and `callbacks` arguments are optional.

```lua
net:add({   -- provide a new value
  mode = 'auto'
  },{
  success = print, -- called when the state has been successfully removed from the daemon
  error = print -- callled when the state could be removed from the daemon
})
```

```lua
net:add(nil,{  -- keep state's value
  success = print, -- called when the state has been successfully removed from the daemon
  error = print -- callled when the state could be removed from the daemon
})
```

### [current_val] = state:value([new_val])

If `new_val` is `nil` returns the state's current value. Else posts a change notification for this state.

```lua
local val = a_state:value() -- read current val
a_state:value(val+1) -- post a state change
```
