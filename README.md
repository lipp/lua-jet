# About

lua-jet is a [Jet](http://jetbus.io) daemon and peer implementation written in Lua. 
[![Build Status](https://travis-ci.org/lipp/lua-jet.png?branch=master)](https://travis-ci.org/lipp/lua-jet/builds)

# Installation

    $ git clone https://github.com/lipp/lua-jet.git
    $ cd jet
    $ sudo luarocks make rockspecs/lua-jet-scm-1.rockspec

# Running the daemon

    $ jetd.lua

# Starting an example peer

    $ cd lua-jet
    $ lua example/some_service.lua

# Radar

[Radar](http://github.com/lipp/radar) is a web application that gives you access to a Jet bus.

    $ sudo luarocks install orbit
    $ git clone https://github.com/lipp/radar
    $ cd radar 
    $ ./simple_webserver.lua

Watch Your Jet Bus on [Your local Radar](http://localhost:8080).

# Doc

For general information, visit the [Jet Homepage](http://jetbus.io). Look at the [API.md](https://github.com/lipp/lua-jet/blob/master/API.md), the [examples](https://github.com/lipp/lua-jet/tree/master/examples) or the [busted](https://github.com/lipp/busted/tree/add-finally) test [spec files](https://github.com/lipp/lua-jet/tree/master/spec).

# Tests

To run the tests, [busted with finally support](https://github.com/lipp/busted/tree/add-finally) needs to be installed:

    $ git clone https://github.com/lipp/busted.git
	$ cd busted
    $ git checkout add-finally
	$ ./try
	
If all is in place, run the tests from within the lua-jet dir like this:

    $ busted spec
