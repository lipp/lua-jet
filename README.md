# About

Jet is a protocol on top of JSON-RPC which allows building efficient, distributed, hot-plugable, asynchronous, event driven, all-buzzing applications. In short: Jet allows building a true object bus made up of:
- __hierachy__
- __states__
- __methods__
This package provides a Jet compatible daemon (which happens to be written in Lua) and Lua peer bindings.
Jet prescribes simple concepts to allow building very complex distributed applications. It tries to be simpler and more transparent than DBus, while at the same time being more flexible.

# What you get

- distributing states and methods with arbitrary hierarchy among arbitrary processes
- events for creation, deletion and change of nodes, states and methods
- automatic node management
- hot-plugable infrastructure
- simple yet powerful concepts

# What you need

To implement your own daemon or client binding you will need:

- Sockets
- JSON parser
- Some event-loop or threads

# Concepts

## Daemon

The jet daemon has three main jobs:

- Managing nodes and leaves
- Routing __call__ and __set__ messages to the right peers
- Distributing Posts to all peers interested (aka "fetch/unfetch" or "publish/subscribe")

### Nodes and leaves (hierarchy)

Jet is built to allow distributing functionality between processes as fine as possible. Since Nodes are managed by the daemon, processes can embed their leaves (states and methods) at any possible node as long as this position is free (not already occupied by a node or another leave). In opposite to DBus, related functionality can be provided by different processes (different peers in jet terminology). E.g. peer 1 could provide a state 'foo.bar.status' and peer 2 could provide a method 'foo.bar.fly'. A jet peer using either of the functionality be __set__ or __call__ does not see peer boundaries though.

Therefor it is __easy__ to change service distribution, since other peers will not even notice a change.

The daemon manages creation and deletion of node. As soon as a new node is required, it is created (and posted/published to all peer interested). The other way around, if a node has no longer any child, it is deleted (and posted/published to all peer interested).

### Routing

Calls __set__
