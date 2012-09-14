# Conventions

As described [here](http://www.jsonrpc.org/specification#conventions)

A __peer__ is a process which interacts with the jet daemon.

# Message wireformat

32bit big-endian denoting the payload length, followed by the message payload, which MUST be JSON.

# Message types

## Request Object

A message with payload as defined [here](http://www.jsonrpc.org/specification#request_object).

## Response Object

A message with payload as defined [here](http://www.jsonrpc.org/specification#response_object).

## Notification Object

A message with payload as defined [here](http://www.jsonrpc.org/specification#notification).

## Batch

A message with a JSON Array as payload, which contains an arbitrary sequence of Response/Request/Notification Objects.


# Jet Services

The jet daemon provides several services which may be used through:
- sending a __Request Object__; the daemon will process the message and reply with a corresponding __Response Object__
- sending a __Notification Object__; the daemon will process the message but will __NOT__ reply

To execute a jet service set the Request's/Notification's field __method__ to the service name and set the field __params__ as required by the service.

## add [path,element]

Adds an element to the internal jet tree. The element may either describe a method or a state. After adding, the peer gets forwarded __set__ (state) and __call__ (method) Requests / Notifications. The peer is responsible for processing the message and reply with a Response Object if the message is a Request.

### path (String)

The element's path, '/' (forward-slash) for delimiting nodes.

### element (Object)

MUST contain the fields:

- __type__: either 'state' or 'method'

MAY contain the fields:

- __schema__: a string which describes the element
- __value__: the current value, only applies for states

### Sideeffects

MUST post a Notification for the newly added element, like:
```Javascript
{
        "method":...
        "params":{
                "event":"add",
                "path": path,
                "data": element
        }
}
```

MAY post a Notification for implicitly added nodes, like:
```Javascript
{
        "method":...
        "params":{
                "event":"add",
                "path": subpath,
                "data": {
                        "type":"node"
                }               
        }
}
```

### Forwards

Note that the forwarded message may be a Notification (no 'id'). In this case, a Response MUST NOT be send.

#### set
__set__ service request will be forwarded as follows (imagine a state 'a/b/c' has been added):
```Javascript
var set_msg = 
{
        "id":231, // optional
        "method":"set",
        "params":{
                "path":"a/b/c",
                "value": 123
        }
}
var set_forward = 
{
        "id": 231, // optional
        "method":"a/b/c",
        "params":[123]
}
```

__call__ service request will be forwarded as follows (imagine a state 'a/b/d' has been added):
```Javascript
var call_msg = 
{
        "id": 231, // optional
        "method":"call",
        "params":{
                "path":"a/b/d",
                "args": [1,2]
        }
}
var call_forward = 
{
        "id": 231, // optional
        "method":"a/b/c",
        "params":[1,2]
}
```


## remove [path]

Removes the (leave) element with the specified path. __call__ and __set__ messages will no longer be forwarded.

### path (String)

The element's path, '/' (forward-slash) for delimiting nodes.

## call [path,args]

Calls a previously a added method with the specified arguments. The method may have been registered by the calling process or any other process connected to jet. 

The jet daemon will try to forward the request to a peer.

### path (String)

The element's path, '/' (forward-slash) for delimiting nodes.

### args (Array)

The arguments Array which will be forwarded to the peer.

## set [path,value]

Sets the element's value.

The jet daemon will try to forward the request to a peer.

### path (String)

The element's path, '/' (forward-slash) for delimiting nodes.

### value (any JSON)

The desired value's type cannot be determined previously and will be accepted / refused be the processing peer on message arrival.

### Sideeffects

Even if the service returns with no error, the actual state's value might differ from the requested one. The peer SHOULD listen to state changes via fetch to retrieve the 'real' new value.

## post [path,notification]

Posts the specified notification to all 'fetchers', which match on path's value.

### path (String)

The element's path, '/' (forward-slash) for delimiting nodes.

### notification (Object)

MUST contain the fields:

- __event__: MUST be 'change' for now
- __path__


## fetch [id,matcher]

### id (String)

An id which will be delivered back to the peer, whenever a notification is being posted, where the path is matched by matcher.

### matcher (String or Object)

If matcher is a String, it must be a Lua pattern.

### Sideeffects

The peer gets 'add' notifications for all existing matched nodes, states and methods as if they were just added. All future matched posted notifications are forwarded as well.

### Forwards

Imagine a state 'change' post, which is matched be the fetcher with id = 'foo'.
```Javascript
var incoming_post = 
{
        "method":"post",
        "params":{
                "path":"a/b/c",
                "event": "change",
                "data": 83373.22
        }
}
var post_forward = 
{
        "method":"foo",
        "params": {
                "path":"a/b/c",
                "event": "change",
                "data": 83373.22
        }
}
```

## unfetch [id]









