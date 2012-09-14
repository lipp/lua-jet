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

# What you need

- Sockets
- JSON parser
- Some event-loop or threads

