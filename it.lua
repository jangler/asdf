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

  -- TODO read patterns (skip instruments and samples)

  return setmetatable(mod, File_mt), nil
end

-- write the IT module to a file
function File:write(f)
  -- determine stuff for offsets
  local patternoffsets = {}
  for i, pattern in ipairs(self.patterns) do
    -- TODO
  end
  local messageoffset = 0  -- TODO

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

  -- TODO write message (remember to gsub('\n', '\r'))
  -- TODO write patterns
end

return {
  new = new,
  read = read,
}
