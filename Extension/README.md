# Introduction

You can use the Lua Debugger extension to debug Lua programs with Visual Studio Code.


# Requirements

- You should be able to use `luasocket` in a Lua program to be debugged.
- You should be able to use a JSON library in a Lua program to be debugged.  
`cjson` and` dkjson` are recommended, but you can use other JSON libraries whose interfaces are compatible.
- Your code or third party library should not call `debug.sethook`.



# Configuration

In order to debug Lua programs with Lua Debugger, you have to put vscode-debuggee.lua in the program to be debugged.  
If you have used mobdebug, you are familiar with it.



## Debugger Connection

1. Download [vscode-debuggee.lua](https://github.com/devcat-studio/VSCodeLuaDebug/blob/master/debuggee/vscode-debuggee.lua) and put it in your project.

2. Paste the following code into your program to run after all the Lua source code is loaded.  
Depending on which JSON library you are using, you may need to modify your code accordingly.
  ```lua
local json = require 'dkjson'
local debuggee = require 'vscode-debuggee'
local startResult, breakerType = debuggee.start(json)
print('debuggee start ->', startResult, breakerType)
  ```

3. Open the folder that contains the program you want to debug in Visual Studio Code,
open the Debug window with `Ctrl-Shift-D`,
and edit the debugging settings accordingly.

4. Set the breakpoint by pressing `F9` at the appropriate location in the program to be debugged.

5. Press the `F5` key to start debugging.



## Setting to Enter the Debugger When an Error Occurs

Paste the following code at the location where you want to handle the error.
```lua
xpcall(
    function()
        -- Code to actually run
        local a = 1 + nil
    end,
    function(e)
        if debuggee.enterDebugLoop(1, e) then
            -- ok
        else
            -- If the debugger is not attached, enter here.
            print(e)
            print(debug.traceback())
        end
    end)
```


## Enabling Debug Commands to be Processed During Execution

To enable the Lua program to respond to commands from the debugger, such as setting a pause or a breakpoint, while running, set the following code to be called at appropriate intervals.

If your project is a game client, you can call it every frame.
```lua
debuggee.poll()
```

# Gideros Support

You can run Gideros Player directly from Visual Studio Code.  
Please refer to the 'launch-gideros' section of the debugging settings.


# Remote Debugging

If you set the debugging setting to `wait` and start debugging, Visual Studio Code will wait for a debuggee without executing one.  
This is useful if you want to see the string that the debugging target leaves on the console, or if the debugger and the debugging target must be running on different machines.


# OP_HALT Patch

Basically `Vscode-debuggee.lua` drops the speed of running Lua programs because it implements the breakpoint mechanism using `debug.sethook`.  
This performance degradation can be overcome by applying a simple patch to the Lua VM.

A patch file for lua 5.1.5 is available [here](https://github.com/devcat-studio/lua-5.1.5-op_halt/blob/master/op_halt.patch).

The result of applying this patch to lua 5.1.5 can be downloaded [here](https://github.com/devcat-studio/lua-5.1.5-op_halt).



# Acknowledgments

- The `OP_HALT` patch relies heavily on the [work mentioned in the Lua mailing list](http://lua-users.org/lists/lua-l/2010-09/msg00989.html). Thanks to Dan Tull.

- We got an idea from [`mobdebug`](https://github.com/pkulchenko/MobDebug) about how to connect the debuggee to the debugger. Thanks to Paul Kulchenko.

- Thanks to Google Translator for translating this article!


# vscode-debuggee.lua Reference

## debuggee.start(jsonLib, config)
Connect with the debugger. `jsonLib` is a JSON library containing `.encode` and `.decode` functions.  
`Config.onError` is a callback to receive when an error occurs in the` vscode-debuggee` module.  
`Config.connectTimeout`,` config.controllerHost`, and `config.controllerPort` are settings for remote debugging.
If `config.redirectPrint` is true, the `print` call is intercepted and displayed in the Visual Studio Code output window. Use this item if you want Gideros to print the results of a `print` called just before the breakpoint.

`debuggee.start` returns two values. The first return value is `true` if it is normally connected to the debugger, otherwise it is` false`. If the `OP_HALT` patch is applied in the current Lua VM, the second return value is `'halt'`, otherwise it is `'pure'`.

## debuggee.poll()
Processes queued debugging commands and returns immediately.

## debuggee.enterDebugLoop(depth[, what])
Stops running the Lua program and start debugging from the current location.  
`depth` specifies the relative depth of the stack to indicate where the debugger is currently running. 0 means the place to call `debuggee.enterDebugLoop`, and 1 means a step shallow.  
`what` is the message you want to pass to the Visual Studio Code as you start debugging.  
