-- impulse tracker file format
--
-- see ITTECH.TXT (elsewhere) for documentation on the IT module format.
--
-- one note: words are big-endian in this format.

local SIGNATURE = 'IMPM'

-- bit flags for byte $2C
local FLAG_STEREO = 0x01
local FLAG_VOL0MIX = 0x02
local FLAG_USEINSTRUMENTS = 0x04
local FLAG_LINEARSLIDES = 0x08
local FLAG_OLDEFFECTS = 0x10
local FLAG_COMPATIBLEGXX = 0x20
local FLAG_USEMIDIPITCH = 0x40
local FLAG_EMBEDDEDMIDI = 0x80

-- bit flags for byte $2E
local SPECIAL_MESSAGEATTACHED = 0x01
local SPECIAL_EMBEDDEDMIDI = 0x04

local File = {}
local File_mt = { __index = File }

-- create and return a new IT moduke (as if if were read from a new file)
local function new()
  local mod = {
    songname = '',
    hilightminor = 4,
    hilightmajor = 16,
    orders = {},
    patterns = {},
    cwtv = 0x1702,  -- for some reason IT v2.14 writes this and not 0x1402
    cmwt = 0x1402,
    flags = FLAG_LINEARSLIDES & FLAG_STEREO,
    special = 0x06,  -- from IT v2.14; no idea what this means…
    globalvol = 128,
    mixingvol = 48,
    initialspeed = 6,
    initialtempo = 125,
    separation = 128,
    pwd = 0,
    message = '',
    channelpan = {},
    channelvol = {},
  }
  for i = 1, 64 do
    mod.channelpan[i], mod.channelvol[i] = 32, 64
  end
  return setmetatable(mod, File_mt)
end

-- create and return a blank 64-row pattern
local function newpattern()
  local rows = {}
  for i = 1, 64 do
    rows[i] = {}
  end
  return rows
end

-- read a pattern from a file
local function readpattern(f)
  -- TODO do this correctly
  local length, numrows = ('HHxxxx'):unpack(f:read(8))
  local rows = {}
  local maskvars = {}
  for i = 1, numrows do
    local chanvar, channels = ('B'):unpack(f:read(1)), {}
    local maskvar = maskvars[chanvar]
    while chanvar ~= 0 do
      local cell = {}
      if chanvar & 128 ~= 0 then
        maskvar = ('B'):unpack(f:read(1))
      else
        maskvar = maskvars[chanvar]
      end
      maskvar = maskvar == nil and 0 or maskvar
      if maskvar & 1 ~= 0 then cell.note = ('B'):unpack(f:read(1)) end
      if maskvar & 2 ~= 0 then cell.inst = ('B'):unpack(f:read(1)) end
      if maskvar & 4 ~= 0 then cell.volpan = ('B'):unpack(f:read(1)) end
      if maskvar & 8 ~= 0 then
        cell.cmd, cell.cmdval = ('BB'):unpack(f:read(2))
      end
      channels[chanvar & 0x7F] = cell
      chanvar = ('B'):unpack(f:read(1))
      maskvars[chanvar] = maskvar
    end
    rows[i] = channels
  end
  return rows
end

-- returns itfile, error
local function read(f)
  if f:read(4) ~= SIGNATURE then return nil, 'not an IT module' end

  -- read header
  local mod = { songname = ('c26'):unpack(f:read(26)) }
  mod.orders, mod.patterns, mod.channelpan, mod.channelvol = {}, {}, {}, {}
  mod.hilightminor, mod.hilightmajor = ('BB'):unpack(f:read(2))
  local ordnum, insnum, smpnum, patnum = ('HHHH'):unpack(f:read(8))
  mod.cwtv, mod.cmwt, mod.flags, mod.special = ('HHHH'):unpack(f:read(8))
  mod.globalvol, mod.mixingvol = ('BB'):unpack(f:read(2))
  mod.initialspeed, mod.initialtempo = ('BB'):unpack(f:read(2))
  mod.separation, mod.pwd = ('BB'):unpack(f:read(2))
  local msglength, msgoffset = ('HI'):unpack(f:read(6))
  f:seek("cur", 4)  -- reserved
  for i = 1, 64 do mod.channelpan[i] = ('B'):unpack(f:read(1)) end
  for i = 1, 64 do mod.channelvol[i] = ('B'):unpack(f:read(1)) end
  for i = 1, ordnum do mod.orders[i] = ('B'):unpack(f:read(1)) end
  f:seek("cur", insnum * 4)
  f:seek("cur", smpnum * 4)
  local patoffsets = {}
  for i = 1, patnum do patoffsets[i] = ('I'):unpack(f:read(4)) end

  -- read message, if there is one
  if mod.flags & SPECIAL_MESSAGEATTACHED then
    f:seek("set", msgoffset)
    mod.message = f:read(msglength):gsub('\r', '\n')
  else
    mod.message = ''
  end

  -- read patterns (skip instruments and samples)
  for i, offset in ipairs(patoffsets) do
    if offset == 0 then
      -- empty pattern
      mod.patterns[i] = newpattern()
    else
      f:seek("set", offset)
      mod.patterns[i] = readpattern(f)
    end
  end

  return setmetatable(mod, File_mt), nil
end

-- write the IT module to a file
function File:write(f)
  -- determine stuff for offsets
  local patternoffsets = {}
  for i, pattern in ipairs(self.patterns) do
    -- TODO
  end
  local messageoffset = (0xC0 + #self.orders + #self.instruments*4 +
    #self.patterns*4)

  -- write header
  f.write(SIGNATURE)
  f.write(('c26'):pack(self.songname))
  f.write(('BB'):pack(self.hilightminor, self.hilightmajor))
  f.write(('>HHHH'):pack(#self.orders, 0, 0, #self.patterns))
  f.write(('>HHHH'):pack(self.cwtv, self.cmwt, self.flags, self.special))
  f.write(('BB'):pack(self.globalvol, self.mixingvol))
  f.write(('BB'):pack(self.initialspeed, self.initialtempo))
  f.write(('BB'):pack(self.separation, self.pwd))
  f.write(('>HIxxxx'):pack(#self.message, messageoffset))

  -- write channel panning and volume
  for _, pan in ipairs(self.channelpan) do
    f.write(('B'):pack(pan))
  end
  for _, vol in ipairs(self.channelvol) do
    f.write(('B'):pack(vol))
  end

  -- write order list
  for _, order in ipairs(self.orders) do
    f.write(('B'):pack(order))
  end

  -- write pattern offsets
  for _, offset in patternoffsets do
    f.write(('>I'):pack(offset))
  end

  f:write(self.message:gsub('\n', '\r'))
  -- TODO write patterns
end

-- print a textual representation of pattern i (1-indexed) to file f
function File:printpattern(i, f)
  -- TODO intelligently only print as many channels as necessary
  for i, row in ipairs(self.patterns[i]) do
    local channels = {}
    for j = 1, 4 do
      if row[i] == nil then
        channels[j] = '...----.00'
      else
        channels[j] = 'YESyeahYES'
      end
    end
    f:write(('%03d '):format(i - 1) .. table.concat(channels, ' ') .. '\n')
  end
end

return {
  new = new,
  read = read,
}
