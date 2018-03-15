package.path = '..\\..\\..\\?.lua;?.lua'

-- time things ...
local getTime = function() return 0 end
local hassocket, socket = pcall(require, 'socket')
if socket and socket.gettime then getTime = socket.gettime end


local function testIt()
  local startTime = getTime()

  args = '-noffi'
  dofile('..\\..\\bench\\scimark.lua')

  local endTime = getTime()
  local diff = (endTime - startTime)
  print('test result: ' .. diff .. ' s')
  return diff
end

local a = testIt()

require('vscode-debuggee').start()

local b = testIt()

print('Debugger is ' .. (b/a) .. ' x slower (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')')
