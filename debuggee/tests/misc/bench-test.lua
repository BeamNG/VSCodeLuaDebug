package.path = '..\\..\\..\\?.lua;..\\..\\bench\\?.lua;?.lua'

-- helper things
local getTime = function() return 0 end
local hassocket, socket = pcall(require, 'socket')
if socket and socket.gettime then getTime = socket.gettime end
local testName = tostring(arg[1])
arg = table.remove(arg, 1)
--print(" testName = " .. tostring(testName))

local function testIt()
  args = '-noffi'
  package.loaded['scimark'] = nil
  collectgarbage()

  local startTime = getTime()

  local s = require('scimark')

  local endTime = getTime()
  local diff = (endTime - startTime)
  print('test result: ' .. diff .. ' s')
  return diff
end

local a1 = testIt() -- this is supposed to cache everything for the first test

local a = testIt()

require('vscode-debuggee').start()

local b = testIt()

print('Debugger is ' .. (b/a) .. ' x slower (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')')

file = io.open ('..\\..\\benchresults.csv', 'a')
file:write(testName .. ', ' .. tostring(a) .. ', ' .. tostring(b) .. "\n")
file:close()
