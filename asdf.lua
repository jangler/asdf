-- abstract song data format
--
-- header:
-- $00  4  (char)   literal 'ASDF'
-- $04  32 (char)   song title (utf-8)
-- $24  1  (byte)   RLE escape byte
-- $25  1  (byte)   speed (ticks per row)
-- $26  2  (word)   tempo (ticks per minute)
-- $28  1  (byte)   number of orders
-- $29  1  (byte)   number of patterns
-- $2A  ?  (byte)   orders
--
-- patterns:
-- +$00 1  (byte)   number of rows
-- +$01 1  (byte)   number of channels
-- +$02 2  (word)   length of compressed data
-- +$04 ?  (array)  channels
--   of 6  (array)  columns
--   of ?  (record) cell, 8 bytes:
--                  - note ($40->$B7 = pitch, $FF = off, $00 = blank)
--                  - instrument ($01->$FF, $00 = blank)
--                  - volume ($40->$C0, $00 = blank)
--                  - panning ($40->$C0, $00 = blank)
--                  - effect1 ($00->$xx, $00 does nothing)
--                  - param1 ($00->$FF, $00 by default)
--                  - effect2 ($00->$xx, $00 does nothing)
--                  - param2 ($00->$FF, $00 by default)
--
-- patterns are RLE-compressed, using the escape byte defined at the beginning
-- of the file. when the escape byte is encountered, the following byte is the
-- length of the run, and the byte after is the fill byte.

local SIGNATURE = 'ASDF'

local Module = {}
local Module_mt = { __index = Module }

-- RLE-compresses a table of integers into a new table
local function rlencode(buf, escbyte)
  local out, runlen, runbyte = {}, 1, nil
  for i = 1, #buf + 1 do  -- get extra nil value to trigger flush
    local byte = buf[i]
    if byte == runbyte then
      runlen = runlen + 1
    elseif runlen > 3 or runbyte == escbyte then
      out[#out+1] = escbyte
      out[#out+1] = runlen - 1
      out[#out+1] = runbyte
      runlen = 1
    else
      if runbyte then out[#out+1] = runbyte end
      runlen = 1
    end
    runbyte = byte
  end
  return out
end

-- reads a RLE-decoded table of integer values from a file
local function rldecode(f, len, escbyte)
  local buf, byte = {}, ('B'):unpack(f:read(1))
  for i = 1, len do
    if byte ~= escbyte then
      buf[#buf+1] = byte
    else
      local runlen, runbyte = ('BB'):unpack(f:read(2))
      for i = 1, runlen do
        buf[#buf+1] = runbyte
      end
    end
  end
  return buf
end

-- reads an ASDF module from a file, returning mod and error
local function read(f)
  if f:read(4) ~= SIGNATURE then return nil, 'not an asdf file' end

  local mod = {
    title = ('c32'):unpack(f:read(32)),
    orders = {},
    patterns = {},
  }
  local escbyte = ('B'):unpack(f:read(1))
  mod.speed, mod.tempo = ('BH'):unpack(f:read(3))
  local numorders, numpatterns = ('BB'):unpack(f:read(2))
  for i = 1, numorders do
    mod.orders[i] = ('B'):unpack(f:read(1))
  end
  for i = 1, numpatterns do
    local offset = ('I'):unpack(f:read(4))
    f:seek("set", offset)
    local nrows, nchannels, datalen = ('BBH'):unpack(f:read(4))
    local buf = rldecode(f, escbyte)
    local pattern = {}
    for i = 1, nrows do
      pattern[i] = {}
      for j = 1, nchannels do
        local cell = {}
        -- TODO: do this with unpack
        cell.note = buf[(nrows * j + i) * 8 + 0]
        cell.note = buf[(nrows * j + i) * 8 + 1]
        cell.note = buf[(nrows * j + i) * 8 + 2]
        cell.note = buf[(nrows * j + i) * 8 + 3]
        cell.note = buf[(nrows * j + i) * 8 + 4]
        cell.note = buf[(nrows * j + i) * 8 + 5]
        cell.note = buf[(nrows * j + i) * 8 + 6]
        cell.note = buf[(nrows * j + i) * 8 + 7]
        pattern[i][j] = cell
      end
    end
  end

  return setmetatable(mod, Module_mt), nil
end

-- creates a new blank ASDF module
local function new()
  local mod = {
    title = '',
    orders = {},
    patterns = {},
    speed = 6,
    tempo = 750,
  }
  return setmetatable(mod, Module_mt)
end

-- convert another format that implements the ASDF interface
local function import(src)
  local mod = {
    title = src:gettitle(),
    speed = src:getspeed(),
    tempo = src:gettempo(),
    orders = src:getorders(),
    patterns = src:getpatterns(),
  }
  return setmetatable(mod, Module_mt)
end

-- writes an ASDF module to a file
function Module:write(f)
  local escbyte = 0xEE  -- TODO: choose escape byte more intelligently
  f:write(SIGNATURE)
  f:write(('c32'):pack(self.title))
  f:write(('B'):pack(escbyte))
  f:write(('BHBB'):pack(self.speed, self.tempo, #self.orders, #self.patterns))
  for _, v in ipairs(self.orders) do
    f:write(('B'):pack(v))
  end
  for _, pattern in ipairs(self.patterns) do
    local buf = {}
    for chan = 1, #pattern[1] do
      for col = 1, 8 do
        for row = 1, #pattern do
          buf[#buf+1] = pattern[row][chan][col]
        end
      end
    end
    local packdata = rlencode(buf, escbyte)
    f:write(('BBH'):pack(#pattern, #pattern[1], #packdata))
    for _, v in ipairs(packdata) do
      f:write(('B'):pack(v))
    end
  end
end

return {
  new = new,
  read = read,
  import = import,
}
