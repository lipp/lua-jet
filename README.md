# About

jet is a message based framework for distributed applications in Lua (and other languages).

jet is zbus + hierarchy + JSON.

# Concepts
jet differs three types of entities:

- properties
- methods
- monitors

# Caching

# Commands

## jet.add

Adds the specified entity to the node cache. jet.add recursively adds nodes if neccessary.
The arguments are the (full) name of the entity and a description. Hierarchy is implied by '.', e.g. 'some.thing.bla' implies that 'some' and 'thing' are nodes. This has not to worry you: jet checks this for you and automatically creates (and posts) the the nodes (from inside out). The description will be returned from '...:list' on the corresonding parent node.



