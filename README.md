# Conventions

As described [here](http://www.jsonrpc.org/specification#conventions)

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
- sending a __Request Object__; the daemon will process the request and reply with a corresponding __Response Object__
- sending a __Notification Object__; the daemon will process the request but will __NOT__ reply

To execute a jet service set the Request's/Notification's field __method__ to the service name and set the field __params__ as required by the service.

## add [path,element]

Adds an element to the internal jet tree. The element may either describe a method or a state.

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

## remove [path]

### path (String)

## call [path,args]

### path (String)

### args (Array)

## notify [path,notification]

### path (String)

### notification (Object)

## fetch [id,matcher]

### id (String)

### matcher (String or Object)

## unfetch [id]









