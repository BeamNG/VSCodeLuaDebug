--[[
Copyright (c) NEXON Korea Corporation
Copyright (c) BeamNG GmbH

All rights reserved.

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

how to use:

require('vscode-debuggee').start()

--]]

local M = {}

local enableLuaJIT = true -- if available - set to false for debugging

local hassocket, socket = pcall(require, 'socket')
local json
local handlers = {}
local sock = nil

local sourceBasePath = ''
local storedVariables = {}
local nextVarRef = 1
local ignoreFirstFrameInC = false
local debugTargetCo = nil
local originalPrintFunction = nil

local instanceName = tostring(M)
local logtag = 'debugger.' .. instanceName

local filename_self = debug.getinfo(1, 'S').source:match(".-([^\\/]-[^%.]+)$") -- gets the current filename of this file

local breakFileMap = {}
local normalBreakPoints = {}

local coroutineSet = {}
setmetatable(coroutineSet, { __mode = 'v' }) -- mark it as weak table: do not free the values

local debugComm = function() end
local sockArray = {}

local lastHaltInfo = nil

-- placeholder for a more advanced inspection method. Used in error messages and alike
function simpleDump(o)
  if type(o) == 'table' then
     local s = '{ '
     for k,v in pairs(o) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s = s .. '['..k..'] = ' .. simpleDump(v) .. ','
     end
     return s .. '} '
  else
     return tostring(o)
  end
end
local dumps = dumps or simpleDump

-- make sure sethook is not use by anyone else by overloading the API :)
local sethook, d_getinfo = debug.sethook, debug.getinfo
local string_find, string_sub = string.find, string.sub
debug.sethook = nil

-- overload coroutine.create to be able to notify the remote debugger
local cocreateOriginal = coroutine.create
coroutine.create = function(f)
  local c = cocreateOriginal(f)
  M.addCoroutine(c)
  return c
end

local function defaultLogFunc(level, origin, msg)
  print(tostring(level) .. '|' .. tostring(origin) .. '|' .. tostring(msg))
end

local log = defaultLogFunc

-- converts VSCode paths to local paths
-- should be overriden in the config, the default just passes it through
local function vsCodePathToLocalPathDefault(filename, sourceBasePath)
  local res = filename
  --[[
  if sourceBasePath:len() > 0 and res:sub(1, sourceBasePath:len()) == sourceBasePath then
    res = res:sub(sourceBasePath:len() + 1)
    local firstChar = res:sub(1, 1)
    -- remove leading slashes if they are leftovers from the trimming above
    if firstChar == '/' or firstChar == '\\' then
      res = res:sub(2)
    end
  end
  --]]
  -- make the drive letter if present is lower case
  if res:sub(2,2) == ':' then
    res = string.lower(res:sub(1,1)) .. res:sub(2)
  end
  -- we save the entries in the map with a preceding @ symbol
  res = '@' .. res
  log('D', logtag .. 'VS2Lua', tostring(filename) .. ' > ' .. tostring(res))
  return res
end
local vsCodePathToLocalPath = vsCodePathToLocalPathDefault

local function localPathToVSCodePathDefault(filename, sourceBasePath)
  local res = filename
  if res:sub(2,2) ~= ':' and res ~= '=[C]' then
    res = sourceBasePath .. '\\' .. filename
  end
  log('D', logtag .. 'Lua2VS', tostring(filename) .. ' > ' .. tostring(res))
  return res
end
local localPathToVSCodePath = localPathToVSCodePathDefault

-------------------------------------------------------------------------------
local function debug_getinfo(depth, what)
  if debugTargetCo then
    return debug.getinfo(debugTargetCo, depth, what)
  else
    return debug.getinfo(depth + 1, what)
  end
end

-------------------------------------------------------------------------------
local function debug_getlocal(depth, i)
  if debugTargetCo then
    if debug.getinfo(debugTargetCo, depth, 'l') then
      return debug.getlocal(debugTargetCo, depth, i)
    end
  else
    if debug.getinfo(depth, 'l') then
      return debug.getlocal(depth + 1, i)
    end
  end
end

local function checkBreakInStack()
  for i = 2, 9999 do
    local info = debug.getinfo(i,'S')
    if info == nil then return false end
    local bmap = breakFileMap[info.source]
    --log('D', logtag .. '.checkBreakInStack', "break? " .. tostring(info.source) .. ' = ' .. tostring(bmap))
    if bmap then
      local linestart, lineend = info.linedefined, info.lastlinedefined
      for lineBreakPoint, _ in pairs(bmap) do
        if lineBreakPoint >= linestart and lineBreakPoint <= lineend then
          return true
        end
      end
    end
  end
end

local hookRun = nil
local hookAccurate = nil
local hasprofile, profile = pcall(require, 'jit.profile')
if enableLuaJIT and hasprofile then
  -- Luajit support
  local profile_dumpstack = profile.dumpstack
  local stackBeginAcc = nil
  hookAccurate = function(event)
    local st = profile_dumpstack('pl@', 3)
    stackBeginAcc = stackBeginAcc or string_find(st, '@', 17, true)
    local stackEnd = string_find(st, ':', stackBeginAcc, true)
    if not stackEnd then return end
    local filename = string_sub(st, stackBeginAcc, stackEnd - 1)

    local lineMap = breakFileMap[filename]
    --log('D', logtag .. '.hookAccurate.luajit', "break? " .. tostring(filename) .. ' = ' .. tostring(lineMap))
    if lineMap then
      local info = d_getinfo(2, 'Sl')
      local currentline, linebegin, lineend = info.currentline, info.linedefined, info.lastlinedefined
      local insideRange = false
      for lineBreakPoint, breakPointType in pairs(lineMap) do
        if lineBreakPoint >= linebegin and lineBreakPoint <= lineend then
          insideRange = true
          if breakPointType == 2 then -- stepOut breakType
            breakFileMap[filename][lineBreakPoint] = normalBreakPoints[filename][lineBreakPoint]
            if currentline > lineBreakPoint then
              _G.__halt__()
            end
          else
            if currentline == lineBreakPoint then
              breakFileMap[filename][lineBreakPoint] = normalBreakPoints[filename][lineBreakPoint]
              _G.__halt__()
            end
          end
        end
      end

      if insideRange or event == 'return' then -- return is actually before returning to the parent function. So go bac into line mode and hope for the best
        if event ~= 'line' then
          sethook(hookAccurate, 'l')
        end
      else
        if event == 'line' then
          if checkBreakInStack() == false then
            sethook(hookRun, 'c')
          else
            sethook(hookAccurate, 'cr')
          end
        end
      end
    end
  end

  local stackBegin = nil
  hookRun = function()
    local st = profile_dumpstack('pl@', 4)
    print(">>>> ST = " .. tostring(st))
    stackBegin = stackBegin or string_find(st, '@', 17, true)
    local stackEnd = string_find(st, ':', stackBegin, true)
    if not stackEnd then return end
    local filename = string_sub(st, stackBegin, stackEnd - 1)

    local lineMap = breakFileMap[filename]
    --log('D', logtag .. '.hookRun.luajit', "break? " .. tostring(filename) .. ' = ' .. tostring(lineMap))
    if lineMap then
      local info = d_getinfo(2, 'Sl')
      local currentline, linebegin, lineend = info.currentline, info.linedefined, info.lastlinedefined
      local insideRange = false
      for lineBreakPoint, _ in pairs(lineMap) do
        if lineBreakPoint >= linebegin and lineBreakPoint <= lineend then
          insideRange = true
          if currentline == lineBreakPoint then
            breakFileMap[filename][lineBreakPoint] = normalBreakPoints[filename][lineBreakPoint]
            _G.__halt__()
          end
        end
      end

      if insideRange then -- go into accurate mode
        sethook(hookAccurate, 'lr')
      end
    end
  end

else

  -- Lua support
  hookAccurate = function(event)
    local info = d_getinfo(2, 'S')
    if not info then return end

    local lineMap = breakFileMap[info.source]
    --log('D', logtag .. '.hookAccurate.lua', "break? " .. tostring(info.source) .. ' = ' .. tostring(lineMap))
    if lineMap then
      local currentline = d_getinfo(2, 'l').currentline
      local source, linebegin, lineend = info.source, info.linedefined, info.lastlinedefined
      local insideRange = false
      for lineBreakPoint, breakPointType in pairs(lineMap) do
        if lineBreakPoint >= linebegin and lineBreakPoint <= lineend then
          insideRange = true
          if breakPointType == 2 then -- stepOut breakType
            breakFileMap[source][lineBreakPoint] = normalBreakPoints[source][lineBreakPoint]
            if currentline > lineBreakPoint then
              _G.__halt__()
            end
          else
            if currentline == lineBreakPoint then
              breakFileMap[source][lineBreakPoint] = normalBreakPoints[source][lineBreakPoint]
              _G.__halt__()
            end
          end
        end
      end

      if insideRange or event == 'return' then -- return is actually before returning to the parent function. So go bac into line mode and hope for the best
        if event ~= 'line' then
          sethook(hookAccurate, 'l')
        end
      else
        if event == 'line' then
          if checkBreakInStack() == false then
            sethook(hookRun, 'c')
          else
            sethook(hookAccurate, 'cr')
          end
        end
      end
    end
  end

  hookRun = function()
    local info = d_getinfo(2, 'S')
    local lineMap = breakFileMap[info.source]
    --log('D', logtag .. '.hookRun.lua', "break? " .. tostring(info.source) .. ' = ' .. tostring(lineMap))
    if lineMap then
      local currentline = d_getinfo(2, 'l').currentline
      local linebegin, lineend = info.linedefined, info.lastlinedefined
      local insideRange = false
      for lineBreakPoint, _ in pairs(lineMap) do
        if lineBreakPoint >= linebegin and lineBreakPoint <= lineend then
          insideRange = true
          if currentline == lineBreakPoint then
            breakFileMap[info.source][lineBreakPoint] = normalBreakPoints[info.source][lineBreakPoint]
            _G.__halt__()
          end
        end
      end

      if insideRange then -- go into accurate mode
        sethook(hookAccurate, 'lr')
      end
    end
  end
end

local function hookStep(event)
  _G.__halt__()
end

local function hookStepOut(event)
  local info = d_getinfo(2, 'S')
  sethook(hookRun, 'cr')
end

-- internal: sends strings (use sendMessage instead)
local function _sendString(str)
  if not sock then return end
  local first = 1
  while first <= #str do
    local sent, err = sock:send(str, first)
    if not sent then
      log('E', logtag, 'sock:send() error: ' .. tostring(err))
      M.disconnect()
      break
    elseif sent and sent > 0 then
      first = first + sent;
    end
  end
end

-- Sends can also be blocks.
local function sendMessage(msg)
  local body = json.encode(msg)
  debugComm('D', logtag .. '.com', ' > ' .. tostring(body))
  _sendString('#' .. #body .. '\n' .. body)
end

-- Receive should not be a block ... Um ... Are you okay with the block?
local function recvMessage()
  if not sock then
    --log('E', logtag, 'error receiving message: socket not existing')
    return
  end
  local header = sock:receive('*l')
  if (header == nil) then
    -- When the debugger is down
    return nil
  end
  if (string.sub(header, 1, 1) ~= '#') then
    log('E', logtag, 'unknown header:' .. tostring(header))
  end

  local bodySize = tonumber(header:sub(2))
  local body = sock:receive(bodySize)
  debugComm('D', logtag .. '.com', ' < ' .. tostring(body))

  return json.decode(body)
end


local function sendSuccess(req, body)
  sendMessage({
    command = req.command,
    success = true,
    request_seq = req.seq,
    type = "response",
    body = body
  })
end

local function sendFailure(req, msg)
  sendMessage({
    command = req.command,
    success = false,
    request_seq = req.seq,
    type = "response",
    message = msg
  })
end

local function sendEvent(eventName, body)
  sendMessage({
    event = eventName,
    type = "event",
    body = body
  })
end

-- send log to debug console
local function logToDebugConsole(output, category)
  --dump(output)
  local dumpMsg = {
    event = 'output',
    type = 'event',
    body = {
      category = category or 'console',
      output = output
    }
  }
  sendMessage(dumpMsg)
end

local function printToDebugConsole(...)
  local t = { n = select("#", ...), ... }
  for i = 1, #t do
    t[i] = tostring(t[i])
  end
  sendEvent('output', {
      category = 'stdout',
      output = table.concat(t, '\t') .. '\n' -- Same as default "print" output end new line.
    })
end

local function debugLoop()
  storedVariables = {}
  nextVarRef = 1
  while true do
    local msg = recvMessage()
    if not msg then
      -- Debugger dropped while debugging.
      -- If you redirect the print function, return it to its original state
      M.disconnect()
      break
    end

    local fn = handlers[msg.command]
    if fn then
      local rv = fn(msg)

      -- It's continue, but it feels paradoxical to break
      -- You can break the debug loop to continue the normal execution flow.
      if (rv == 'CONTINUE') then
        break;
      end
    else
      log('E', logtag, 'UNKNOWN DEBUG COMMAND: ' .. tostring(msg.command))
    end
  end
  -- cleanup
  storedVariables = {}
  nextVarRef = 1
end

function M.disconnect()
  if sock == nil then return end -- already disconnected
  if originalPrintFunction then
    _G.print = originalPrintFunction
    originalPrintFunction = nil
  end
  sock = nil
  log('E', logtag, 'connection to VSCode dropped')
end

function M.start(config)
  config = config or {}

  instanceName = config.instanceName or 'main'
  logtag = 'debugger.' .. instanceName

  local connectTimeout = config.connectTimeout or 10.0
  local connectRetries = config.connectRetries or 3
  local controllerHost = config.controllerHost or 'localhost'
  local controllerPort = config.controllerPort or 56789
  log = config.logFunc or defaultLogFunc
  if config.ignoreFirstFrameInC ~= nil then
    ignoreFirstFrameInC = config.ignoreFirstFrameInC
  end
  vsCodePathToLocalPath = config.vsCodePathToLocalPath or vsCodePathToLocalPathDefault
  localPathToVSCodePath = config.localPathToVSCodePath or localPathToVSCodePathDefault
  json = config.json or require('dkjson')
  assert(json)

  -- debug comm:
  if config.debugCommunication then
    debugComm = log
  end

  if socket and socket.tcp then
    -- connect to vscode
    local sleepTime = 1
    local successful = false
    for i = 1, connectRetries do
      --log('I', logtag, 'connecting ... (' .. tostring(i) .. ')')
      local err = nil
      sock, err = socket.tcp()
      if not sock then
        log('E', logtag, 'error creating socket: ' .. tostring(err))
        sock = nil
        socket.sleep(sleepTime)
      else
        sockArray = { sock }
        sock:settimeout(connectTimeout) -- set the timeout for connecting only
        local res, err = sock:connect(controllerHost, tostring(controllerPort))
        if not res then
          if err ~= 'connection refused' then
            log('E', logtag, 'error connecting socket: ' .. tostring(err))
          end
          sock:close()
          sock = nil
          sleepTime = sleepTime * 2 -- sleep longer after every retry
          socket.sleep(sleepTime)
        else
          sock:settimeout() -- block indefinity ater being connected
          sock:setoption('tcp-nodelay', true) -- Setting this option to true disables the Nagle's algorithm for the connection.
          successful = true
          break
        end
      end
    end
    if not successful or not sock then return false end
    --log('I', logtag, 'connected? ' .. tostring(successful) .. ', sock = ' .. tostring(sock))

    -- wait for the first message
    local initMessage = recvMessage()
    --dump(initMessage)
    assert(initMessage and initMessage.command == 'welcome')
    sourceBasePath = initMessage.sourceBasePath

    -- redirect print
    originalPrintFunction = _G.print -- Keep the debugger in case it drops.
    if config.redirectPrint then
      _G.print = printToDebugConsole
    end

    log('I', 'vscode-debuggee', 'started successfully')
  else
    log('E', logtag, 'socket not available, mode only useful for performance testing of the hooking code')
  end

  -- start the hooking action
  sethook(hookRun, 'c')

  -- get the inital config (wait for 10 seconds)
  M.poll(10)

  return true
end

-------------------------------------------------------------------------------
function M.poll(timeoutFirstPackage)
  if not sock then
    --log('E', logtag, 'sock not connected')
    return
  end

  -- Processes commands in the queue.
  -- Immediately returns when the queue is/became empty.
  local timeout = timeoutFirstPackage or 0
  while true do
    local r, w, e = socket.select(sockArray, nil, timeout) -- non blocking
    if e == 'timeout' then
      break
    end

    -- no timeout for all following packages
    timeout = 0

    local msg = recvMessage()
    if not msg then break end

    if msg.command == 'pause' then
      M.enterDebugLoop(1)
      return
    end

    local fct = handlers[msg.command]
    if fct ~= nil then
      local rv = fct(msg)
      -- Ignores rv, because this loop never blocks except explicit pause command.
    else
      log('E', logtag, 'POLL-UNKNOWN DEBUG COMMAND: ' .. dumps(msg.command))
    end
  end
end

-- 'thread: 011DD5B0'
--  12345678^
local function getCoroutineId(c)
  return tonumber(string.sub(tostring(c), 9), 16)
end

function M.addCoroutine(c)
  local cid = getCoroutineId(c)
  coroutineSet[cid] = c
 -- sethook(c, hookfunc, 'l')
end

-------------------------------------------------------------------------------
local function getCurrentThreadId()
  local prefix = instanceName .. '.'
  local c = coroutine.running()
  if c then
    return prefix .. getCoroutineId(c)
  end
  return prefix .. 'main'
end

-------------------------------------------------------------------------------
local function startDebugLoop()
  sendEvent('stopped', {
      reason = 'breakpoint',
      threadId = getCurrentThreadId(),
    })

  local status, err = pcall(debugLoop)
  if not status then
    log('E', logtag, 'Error: ' .. tostring(err))
  end
end

-------------------------------------------------------------------------------
_G.__halt__ = function()
  lastHaltInfo = debug.getinfo(3, 'Sl')
  startDebugLoop()
end

-------------------------------------------------------------------------------
function M.enterDebugLoop(depthOrCo, what)
  if sock == nil then return false end

  debugTargetCo = nil

  startDebugLoop()
  return true
end

-------------------------------------------------------------------------------
-- https://github.com/Microsoft/vscode/blob/master/src/vs/workbench/parts/debug/common/debugProtocol.d.ts
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
function handlers.setBreakpoints(req)
  local bpLines = {}
  for _, bp in ipairs(req.arguments.breakpoints) do
    bpLines[#bpLines + 1] = bp.line
  end

  local path = vsCodePathToLocalPath(req.arguments.source.path, sourceBasePath)
  if not path then
    log('E', logtag, 'unable to resolve path for breakpoints: ' .. tostring(req.arguments.source.path))
    return
  end

  log('D', logtag, 'setBreakpoints: ' .. dumps(path) .. ' / ' .. dumps(bpLines))

  -- convert line array to map for easier lookup
  local lineMap = {}
  local lineMapCopy = {}
  local verifiedLines = {}
  for _, ln in ipairs(bpLines) do
    lineMap[ln] = 0 -- Normal breakType = 0
    lineMapCopy[ln] = 0
    verifiedLines[ln] = ln
  end
  -- associate with the file map
  breakFileMap[path] = lineMap
  normalBreakPoints[path] = lineMapCopy
  --dump(breakFileMap)

  -- send result 'all ok' back
  local breakpoints = {}
  for i, ln in ipairs(bpLines) do
    breakpoints[i] = {
      verified = (verifiedLines[ln] ~= nil),
      line = verifiedLines[ln]
    }
  end

  sendSuccess(req, {
    breakpoints = breakpoints
  })
end

-------------------------------------------------------------------------------
function handlers.configurationDone(req)
  sendSuccess(req, {})
  return 'CONTINUE'
end

-------------------------------------------------------------------------------
function handlers.threads(req)
  local c = coroutine.running()
  local mainThread = {
    id = getCurrentThreadId(),
    name = getCurrentThreadId(),
  }
  sendSuccess(req, {
    threads = { mainThread }
  })
end

-------------------------------------------------------------------------------
function handlers.stackTrace(req)
  --assert(req.arguments.threadId == 'main')

  local stackFrames = {}
  local firstFrame = (req.arguments.startFrame or 0) + 6 -- 6 is the magic value for this to work
  local lastFrame = (req.arguments.levels and (req.arguments.levels ~= 0))
    and (firstFrame + req.arguments.levels - 1)
    or (9999)

  -- if firstframe function of stack is C function, ignore it.
  if ignoreFirstFrameInC then
    local info = debug_getinfo(firstFrame, 'lnS')
    if info and info.what == "C" then
      firstFrame = firstFrame + 1
    end
  end

  -- if firstframe is vsdebuggee, remove it
  local info = debug_getinfo(firstFrame, 'lnS')
  if info and info.source:find(filename_self, 1, true) then
    firstFrame = firstFrame + 1
  end

  for i = firstFrame, lastFrame do
    local info = debug_getinfo(i, 'lnS')
    if (info == nil) then break end
    --print(json.encode(info))

    local src = info.source
    if string.sub(src, 1, 1) == '@' then
      src = string.sub(src, 2) -- Removing the preceding '@'
    end

    local name
    if info.name then
      name = info.name .. ' (' .. (info.namewhat or '?') .. ')'
    else
      name = '?'
    end

    local sframe = {
      name = name,
      source = {
        name = nil,
        path = localPathToVSCodePath(src, sourceBasePath)
      },
      column = 1,
      line = info.currentline or 1,
      id = i,
    }
    stackFrames[#stackFrames + 1] = sframe
  end

  sendSuccess(req, {
    stackFrames = stackFrames
  })
end

-------------------------------------------------------------------------------
local scopeTypes = {
  Locals = 1,
  Upvalues = 2,
  Globals = 3,
}
function handlers.scopes(req)
  local depth = req.arguments.frameId

  local scopes = {}
  local function addScope(name)
    scopes[#scopes + 1] = {
      name = name,
      expensive = false,
      variablesReference = depth * 1000000 + scopeTypes[name]
    }
  end

  addScope('Locals')
  addScope('Upvalues')
  addScope('Globals')

  sendSuccess(req, {
    scopes = scopes
  })
end

-------------------------------------------------------------------------------
local function registerVar(varNameCount, name_, value, noQuote)
  local ty = type(value)
  local name
  if type(name_) == 'number' then
    name = '[' .. name_ .. ']'
  else
    name = tostring(name_)
  end
  if varNameCount[name] then
    varNameCount[name] = varNameCount[name] + 1
    name = name .. ' (' .. varNameCount[name] .. ')'
  else
    varNameCount[name] = 1
  end

  local item = {
    name = name,
    type = ty
  }

  if (ty == 'string' and (not noQuote)) then
    item.value = '"' .. value .. '"'
  else
    item.value = tostring(value)
  end

  if (ty == 'table') or
    (ty == 'function') then
    storedVariables[nextVarRef] = value
    item.variablesReference = nextVarRef
    nextVarRef = nextVarRef + 1
  else
    item.variablesReference = -1
  end

  return item
end

-------------------------------------------------------------------------------
function handlers.variables(req)
  local varRef = req.arguments.variablesReference
  local variables = {}
  local varNameCount = {}
  local function addVar(name, value, noQuote)
    variables[#variables + 1] = registerVar(varNameCount, name, value, noQuote)
  end

  if (varRef >= 1000000) then
    -- Scope.
    local depth = math.floor(varRef / 1000000)
    local scopeType = varRef % 1000000
    if scopeType == scopeTypes.Locals then
      for i = 1, 9999 do
        local name, value = debug_getlocal(depth, i)
        if name == nil then break end
        addVar(name, value, nil)
      end
    elseif scopeType == scopeTypes.Upvalues then
      local info = debug_getinfo(depth, 'f')
      if info and info.func then
        for i = 1, 9999 do
          local name, value = debug.getupvalue(info.func, i)
          if name == nil then break end
          addVar(name, value, nil)
        end
      end
    elseif scopeType == scopeTypes.Globals then
      for name, value in pairs(_G) do
        addVar(name, value)
      end
      table.sort(variables, function(a, b) return a.name < b.name end)
    end
  else
    -- Expansion.
    local var = storedVariables[varRef]
    if type(var) == 'table' then
      for k, v in pairs(var) do
        addVar(k, v)
      end
      table.sort(variables, function(a, b)
        local aNum, aMatched = string.gsub(a.name, '^%[(%d+)%]$', '%1')
        local bNum, bMatched = string.gsub(b.name, '^%[(%d+)%]$', '%1')

        if (aMatched == 1) and (bMatched == 1) then
          -- both are numbers. compare numerically.
          return tonumber(aNum) < tonumber(bNum)
        elseif aMatched == bMatched then
          -- both are strings. compare alphabetically.
          return a.name < b.name
        else
          -- string comes first.
          return aMatched < bMatched
        end
      end)
    elseif type(var) == 'function' then
      local info = debug.getinfo(var, 'S')
      addVar('(source)', tostring(info.short_src), true)
      addVar('(line)', info.linedefined)

      for i = 1, 9999 do
        local name, value = debug.getupvalue(var, i)
        if name == nil then break end
        addVar(name, value)
      end
    end

    local mt = getmetatable(var)
    if mt then
      addVar("(metatable)", mt)
    end
  end

  sendSuccess(req, {
    variables = variables
  })
end

function handlers.continue(req)
  sendSuccess(req, {})
  sethook(hookAccurate, 'l')
  return 'CONTINUE'
end

-- aka: stepOver
function handlers.next(req)
  sendSuccess(req, {})
  local currentline = lastHaltInfo.currentline
  if currentline >= lastHaltInfo.lastlinedefined then
    sethook(hookStep, 'l')
  else
    local source = lastHaltInfo.source
    breakFileMap[source][currentline] = 2 -- stepOut breakType
    sethook(hookAccurate, 'l')
  end
  return 'CONTINUE'
end

function handlers.stepIn(req)
  --print("handlers. >> " .. dumps(req))
  sendSuccess(req, {})
  sethook(hookStep, 'l')
  return 'CONTINUE'
end

function handlers.stepOut(req)
  sendSuccess(req, {})
  local source = lastHaltInfo.source
  breakFileMap[source][lastHaltInfo.lastlinedefined] = 1 -- temporal breakType
  sethook(hookAccurate, 'l')
  return 'CONTINUE'
end

function handlers.evaluate(req)
  --print("handlers.evaluate >> " .. dumps(req))
  -- Prepare source code for execution
  local sourceCode = req.arguments.expression
  if string.sub(sourceCode, 1, 1) == '!' then
    sourceCode = string.sub(sourceCode, 2)
  else
    sourceCode = 'return (' .. sourceCode .. ')'
  end

  -- Environment preparation.
  -- I do not know what to ask, so I copy local, upvalue, global.
  -- Priority is global - up value. - Local order.
  -- Put it on the other side and let the latter overwrite the previous one.
  local depth = req.arguments.frameId
  local tempG = {}
  local declared = {}
  local function set(k, v)
    tempG[k] = v
    declared[k] = true
  end

  for name, value in pairs(_G) do
    set(name, value)
  end

  if depth then
    local info = debug_getinfo(depth, 'f')
    if info and info.func then
      for i = 1, 9999 do
        local name, value = debug.getupvalue(info.func, i)
        if name == nil then break end
        set(name, value)
      end
    end

    for i = 1, 9999 do
      local name, value = debug_getlocal(depth, i)
      if name == nil then break end
      set(name, value)
    end
  else
    -- VSCode may not report depth.
    -- This is the case when only a global name is searched without selecting a specific stack frame.
  end
  local mt = {
    __newindex = function() log('E', logtag, 'assignment not allowed', 2) end,
    --__index = function(t, k) if not declared[k] then log('E', logtag, 'not declared: ' .. tostring(k), 2) end end
  }
  setmetatable(tempG, mt)

  -- loadstring for Lua 5.1
  -- load for Lua 5.2 and 5.3(supports the private environment's load function)
  local fn, err = (loadstring or load)(sourceCode, 'X', nil, tempG)
  if fn == nil then
    sendFailure(req, string.gsub(err, '^%[string %"X%"%]%:%d+%: ', ''))
    return
  end

  -- Execute and send result
  if setfenv ~= nil then
    -- Only for Lua 5.1
    setfenv(fn, tempG)
  end

  local success, aux = pcall(fn)
  if not success then
    aux = aux or '' -- Execution of 'error()' returns nil as aux
    sendFailure(req, string.gsub(aux, '^%[string %"X%"%]%:%d+%: ', ''))
    return
  end

  local varNameCount = {}
  local item = registerVar(varNameCount, '', aux)

  sendSuccess(req, {
    result = item.value,
    type = item.type,
    variablesReference = item.variablesReference
  })
end

-------------------------------------------------------------------------------
return M
