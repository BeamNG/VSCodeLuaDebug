local json = require 'dkjson'

local function onError(e)
	print('[onError]' .. e)
end

local debuggee = (require 'vscode-debuggee')
local startResult, breakerType = debuggee.start(json, { onError = onError, dumpCommunication = true, luaStyleLog = true })
print('debuggee.start(): ', tostring(startResult), breakerType)

local function b()
	print('in function b')
end

local function a(t, ...)
	print('in function a ' .. t.k)
	b()
	print('in function a end')
end

a({k = 10}, 20, 30)
print('in test')
