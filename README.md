This project consists out of three components:

* [DebugAdapter](DebugAdapter/)

This is the c# app that converts the messages from Visual Studio code (that it gets via pipe)
to a Json based protocol. You could also call it the debugger host or server.

* [debuggee](debuggee/)

The lua code that connects to the debugging host. The client side is 100% written in lua and very well
embedable due to that.

* [Extension](Extension/)

The Visual studio code extension that contains the metadata and some configuration to integrate the 
DebugAdapter correctly into the IDE.