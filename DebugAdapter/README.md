This is the C# project that is creating the DebugAdapter for acceping VSCode input/output commands and forwarding them as Json to the Lua debuggee


Terms used:

* CDP = Code debug protocol (this is the protocol used by VSCode via stdin/stdout pipe). See https://code.visualstudio.com/docs/extensionAPI/api-debugging
