-- helper things
local getTime = function() return 0 end
local hassocket, socket = pcall(require, 'socket')
if socket and socket.gettime then getTime = socket.gettime end
local testName = tostring(arg[1])
local arch = tostring(arg[2])

print("- testName = " .. tostring(testName))
print("- arch = " .. tostring(arch))

local function testIt()
  package.loaded['mandelbrot2'] = nil
  collectgarbage()

  local startTime = getTime()

  local s = require('mandelbrot2')

  local endTime = getTime()
  local diff = (endTime - startTime)
  print('test result: ' .. diff .. ' s')
  return diff
end

local a = testIt()

require('vscode-debuggee').start()

local b = testIt()

print('Debugger is ' .. (b/a) .. ' x slower (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')')

file = io.open ('..\\..\\..\\benchresults.csv', 'a')
file:write(testName .. ', ' .. arch .. ', ' .. tostring(a) .. ', ' .. tostring(b) .. "\n")
file:close()
