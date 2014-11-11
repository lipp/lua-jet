# About

lua-jet is a [Jet](http://jetbus.io) daemon and peer implementation written in Lua.
[![Build Status](https://travis-ci.org/lipp/lua-jet.png?branch=master)](https://travis-ci.org/lipp/lua-jet/builds)

# Installation


With luarocks:

    $ sudo luarocks install lua-jet

Most recent github version:

    $ git clone https://github.com/lipp/jet.git
    $ cd jet
    $ sudo luarocks make rockspecs/lua-jet-scm-1.rockspec

# Dependencies

In particular you need libev installed.

Ubuntu / Debian based Linux:

    $ sudo apt-get install libev-dev

OSX with Homebrew:

    $ brew install libev


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

For general information, visit the [Jet Homepage](http://jetbus.io). Look at the [API.md](https://github.com/lipp/lua-jet/blob/master/API.md), the [examples](https://github.com/lipp/lua-jet/tree/master/examples) or the [busted](https://github.com/olivine-labs/busted) test [spec files](https://github.com/lipp/lua-jet/tree/master/spec).

# Tests

To run the tests, busted version 1.11.1  needs to be installed:

    $ sudo luarocks install busted 1.11.1-1

If all is in place, run the tests from within the lua-jet dir like this:

    $ busted spec

For more details on installation and running tests under debian based Linux
see the ".travis.yml" file.
