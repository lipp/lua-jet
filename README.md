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
- sending a Request Object; the daemon will process the request and reply with a corresponding Response Object
- sending a Notification Object; the daemon will process the request but will NOT reply

To execute a jet service set the Request's/Notification's field 'method' to the service name and set the field 'params' as required by the service.

## add [path,element]

Adds an element to the internal jet tree. The element may either describe a method or a state.

### params

#### element

An Object








