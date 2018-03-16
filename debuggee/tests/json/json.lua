--[[
 SJSON Parser for Lua 5.1:

 Copyright (c) 2013-2018 BeamNG GmbH.
 All Rights Reserved.

 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or
 sell copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following conditions:

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
 ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 It decodes SJON format:
  https://github.com/Autodesk/sjson

 Usage:

 -- Lua script:
 local t = Json.Decode(json)

 Notes:
 1) Encodable Lua types: string, number, boolean, table, nil
 2) All control chars are encoded to \uXXXX format eg "\021" encodes to "\u0015"
 3) All Json \uXXXX chars are decoded to chars (0-255 byte range only)
 4) Json single line // and /* */ block comments are discarded during decoding
 5) Numerically indexed Lua arrays are encoded to Json Lists eg [1,2,3]
 6) Lua dictionary tables are converted to Json objects eg {"one":1,"two":2}
 7) Json nulls are decoded to Lua nil and treated by Lua in the normal way

--]]

local M = {}

local table = table
local error = error
local tonumber = tonumber
local setmetatable = setmetatable
local byte, sub, tconcat = string.byte, string.sub, table.concat

local escapes = {
  ['t'] = '\t',
  ['n'] = '\n',
  ['f'] = '\f',
  ['r'] = '\r',
  ['b'] = '\b',
  ['"'] = '"',
  ['\\'] = '\\'
}

local JsonReader = {}
local peekTable = {}

function JsonReader:Match(pat)
  local res = self.s:match(pat, self.i)
  self.i = self.i + (res and res:len() or 0)
  return res
end

function JsonReader:Error(msg)
  local curlen = 0
  local n = 1
  for w in self.s:gmatch("([^\n]*)") do
    curlen = curlen + #w
    if curlen >= self.i then
      error(string.format("%s near line %d, '%s'",msg, n, w:match'^%s*(.*%S)' or ''))
    end
    if w == '' then
      n = n + 1
      curlen = curlen + 1
    end
  end
end

local function parseNumber(self)
  -- Read Number
  local s, i = self.s, self.i + 1
  local c = byte(s, i)
  while (c >= 45 and c <= 57) or c == 43 or c == 101 or c == 69 do -- matches \d-+.eE
    i = i + 1
    c = byte(s, i)
  end
  i = i - 1

  local result = tonumber(sub(s, self.i, i))
  if result == nil then
    self:Error(string.format("Invalid number: '%s'", sub(s, self.i, i)))
  end

  -- 1#INF00 support:
  if i == self.i and byte(s, i + 1) == 35 then -- matches #
    local infend = self.i + 6
    if sub(s, self.i, infend) == "1#INF00" then
      result = math.huge
      self.i = infend
    else
      self:Error(string.format("Invalid number: '%s'", sub(s, self.i, infend)))
    end
  else
    self.i = i
  end

  return result
end

local function error_input(self)
  self:Error('Invalid input')
end

local function readComment(self)
  local s, i = self.s, self.i + 1
  local p = byte(s, i)
  if p == 47 then -- /
    -- Read single line comment "//"
    repeat
      i = i + 1
      p = byte(s, i)
    until p == 10 or p == 13 or p == nil
    self.i = i
  elseif p == 42 then -- *
    -- Read block comment "/*  xxxxxxx */"
    while true do
      i = i + 1
      p = byte(s, i)
      if (p == 42 and byte(s, i+1) == 47) or p == nil then -- */
        break
      elseif p == 47 and byte(s, i+1) == 42 then -- /*
        self:Error("'/*' inside another '/*' comment is not permitted")
      end
    end
    self.i = i + 1
  else
    self:Error('Invalid comment')
  end
end

local function SkipWhiteSpace(self)
::restart::
  local s, i = self.s, self.i + 1
  local p = byte(s, i)
  while p ~= nil and (p <= 32 or p == 44) do -- matches space tab comma newline
    i = i + 1
    p = byte(s, i)
  end

  self.i = i
  if p == 47 then -- matches /
    readComment(self)
    goto restart
  end
  return p
end

local function readString(self)
  -- parse string
  -- fast path
  local s, i = self.s, self.i + 1
  local si = i -- "
  local ch = byte(s, i)
  while ch ~= 34 and ch ~= 92 and ch ~= nil do  -- " \
    i = i + 1
    ch = byte(s, i)
  end

  if ch == 34 then -- "
    local result = sub(s, si, i - 1)
    self.i = i
    return result
  end

  self.i = si
  -- slow path for strings with escape chars
  if ch ~= 92 then -- \
    self:Error("Not closed string")
    return
  end

  local result = {}
  local resultidx = 1
  ch = sub(s, self.i, self.i)
  while ch ~= '"' do
    ch = self:Match('^[^"\\]*')
    result[resultidx] = ch
    resultidx = resultidx + 1
    ch = sub(s, self.i, self.i)
    if ch == '\\' then
      local ch1 = escapes[sub(self.s, self.i + 1, self.i + 1)]
      if ch1 then
        result[resultidx] = ch1
        resultidx = resultidx + 1
        self.i = self.i + 1
      else
        result[resultidx] = '\\'
        resultidx = resultidx + 1
      end
      self.i = self.i + 1 -- "
    end
  end

  return tconcat(result)
end

local function readKey(self, c)
  local key
  local starti = self.i
  if c == 34 then -- '"'
    key = readString(self)
  else
    local s, i = self.s, self.i
    local ch = byte(s, i)
    while (ch >= 97 and ch <= 122) or (ch >= 65 and ch <= 90) or (ch >= 48 and ch <= 57) or ch == 95 do -- [a z] [A Z] or [0 9] or _
      i = i + 1
      ch = byte(s, i)
    end

    local i_1 = i - 1
    key = sub(s, starti, i_1)
    self.i = i_1
  end
  if self.i < starti then
    self:Error(string.format("Expected dictionary key"))
  end
  local delim = SkipWhiteSpace(self)
  if delim ~= 58 and delim ~= 61 then -- : =
    self:Error(string.format("Expected dictionary separator ':' or '=' instead of: '%s'", string.char(delim)))
  end
  return key
end

function JsonReader:New(s)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.s = s
  self.i = 0
  return o
end

local function decode(s)
  local self = JsonReader:New(s)
  local c = SkipWhiteSpace(self)
  if c == 123 or c == 91 then
    return peekTable[c](self)
  else
    local result = {}
    while c do
      result[readKey(self, c)] = peekTable[SkipWhiteSpace(self)](self)
      c = SkipWhiteSpace(self)
    end
    return result
  end
end

-- build dispatch table
do
  for i = 0, 255 do
    peekTable[i] = error_input
  end

  peekTable[123] = function(self) -- {
      -- parse object
      local result = {}
      local c = SkipWhiteSpace(self)
      while c ~= 125 do -- }
        result[readKey(self, c)] = peekTable[SkipWhiteSpace(self)](self)
        c = SkipWhiteSpace(self)
      end
      return result
    end
  peekTable[116] = function(self) -- t
      local s, i = self.s, self.i
      if byte(s, i+1) == 114 and byte(s, i+2) == 117 and byte(s, i+3) == 101 then -- rue
        self.i = i + 3
        return true
      else
        self:Error('Error reading value: true')
      end
    end
  peekTable[110] = function(self) -- n
      local s, i = self.s, self.i
      if byte(s, i+1) == 117 and byte(s, i+2) == 108 and byte(s, i+3) == 108 then -- ull
        self.i = i + 3
        return nil
      else
        self:Error('Error reading value: null')
      end
    end
  peekTable[102] = function(self) -- f
      local s, i = self.s, self.i
      if byte(s, i+1) == 97 and byte(s, i+2) == 108 and byte(s, i+3) == 115 and byte(s, i+4) == 101 then -- alse
        self.i = i + 4
        return false
      else
        self:Error('Error reading value: false')
      end
    end
  peekTable[91] = function(self) -- [
      -- Read Array
      local result = {}
      local tidx = 1
      local c = SkipWhiteSpace(self)
      while c ~= 93 do -- ]
        result[tidx] = peekTable[c](self)
        tidx = tidx + 1
        c = SkipWhiteSpace(self)
      end
      return result
    end
  peekTable[48] = parseNumber -- 0
  peekTable[49] = parseNumber -- 1
  peekTable[50] = parseNumber -- 2
  peekTable[51] = parseNumber -- 3
  peekTable[52] = parseNumber -- 4
  peekTable[53] = parseNumber -- 5
  peekTable[54] = parseNumber -- 6
  peekTable[55] = parseNumber -- 7
  peekTable[56] = parseNumber -- 8
  peekTable[57] = parseNumber -- 9
  peekTable[43] = parseNumber -- +
  peekTable[45] = parseNumber -- -
  peekTable[34] = readString  -- "
end

-- public interface
M.decode = decode
return M
