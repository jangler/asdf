-- shroomplayer sho file format
--
-- thanks to:
-- - strobe and setrodox for creating version 1
-- - rainwarrior for creating versions 2 and 3 for mariopants
-- - b00daw for reverse engineering
--
-- common data:
-- $000 4   (char) literal "shro"
-- $004 1   (byte) sho version
-- $005 2          reserved
-- $007 32  (char) title
-- $027 32  (char) author
-- $047 32  (char) shi filename (sample pack), default "default.shi"
--
-- if version is $01 (shroomplayer) or $02 (mariopants):
-- $067 576 (byte) song data (see "song data format")
-- $2A7 1   (byte) tempo ($00-$9F)
--
-- if version is $02 (mariopants):
-- $2A8 1   (byte) song length in beats ($01-$60)
-- $2A9 1   (byte) song loop flag
-- $2AA 1   (byte) time signature ($00 = 3/4, $01 = 4/4)
--
-- if version is $03 (mariopants extended):
-- $067 2   (word) song length in beats ($0061-$0B40)
-- $069 1   (byte) song loop flag
-- $06A 1   (byte) time signature ($00 = 3/4, nz $01 = 4/4)
-- $06B 1   (byte) tempo ($00-$9F)
-- $05C ?   (byte) song data (see "song data structure")
--      ^ length = song length * 6
--
-- song data structure; beat/channel array in beat-major order w/ 3 channels:
-- +0   1   (byte) pitch ($01-$0D = pitch, $FF = off)
-- +1   1   (byte) instrument ($00-$0E = instrument, $DF = off)

local SIGNATURE = 'shro'  -- begins a .sho file
local SHIFILE_DEFAULT = 'default.shi'

local File = {}
local File_mt = { __index = File }

-- returns a new blank shofile
local function new()
  local shofile = {
    title='',
    author='',
    shifile=SHIFILE_DEFAULT,
    songdata={},
    tempo=80,
    length=96,
    loop=0,
    timesig=1,
  }
  for i = 1, 576, 2 do
    shofile.songdata[i], shofile.songdata[i+1] = 0xFF, 0xDF
  end
  return setmetatable(shofile, File_mt)
end

-- read a shofile from f
local function read(f)
  -- check signature and version validity
  if f:read(4) ~= SIGNATURE then return nil, 'not a sho file' end
  local version = ('B'):unpack(f:read(1))
  if version < 1 or version > 3 then return nil, 'unsupported sho version' end
  f:seek("cur", 2)

  -- common stuff
  local shofile = {
    title=f:read(32):gsub('\0', ''),
    author=f:read(32):gsub('\0', ''),
    shifile=f:read(32):gsub('\0', ''),
    songdata={},
  }

  -- version-specific stuff
  if version == 1 or version == 2 then
    for i = 1, 576 do
      shofile.songdata[i] = ('B'):unpack(f:read(1))
    end
    shofile.tempo = ('B'):unpack(f:read(1))
    if version == 2 then
      shofile.length = ('B'):unpack(f:read(1))
      shofile.loop = ('B'):unpack(f:read(1))
      shofile.timesig = ('B'):unpack(f:read(1))
    end
  else
    assert(version == 3)
    shofile.length = ('H'):unpack(f:read(2))
    shofile.loop = ('B'):unpack(f:read(1))
    shofile.timesig = ('B'):unpack(f:read(1))
    shofile.tempo = ('B'):unpack(f:read(1))
    for i = 1, shofile.length * 6 do
      shofile.songdata[i] = ('B'):unpack(f:read(1))
    end
  end

  return setmetatable(shofile, File_mt)
end

-- write shofile to f
function File:write(f)
  -- use extended version iff song length requires it
  local version = self.length > 96 and 3 or 2

  -- common data
  f:write(SIGNATURE)
  f:write(('B'):pack(version))
  f:write('\0\0')
  f:write(('c32'):pack(self.title))
  f:write(('c32'):pack(self.author))
  f:write(('c32'):pack(self.shifile))

  -- version-specific data
  if version == 1 or version == 2 then
    for _, v in ipairs(self.songdata) do
      f:write(('B'):pack(v))
    end
    f:write(('B'):pack(self.tempo))
    if version == 2 then
      f:write(('B'):pack(self.length))
      f:write(('B'):pack(self.loop))
      f:write(('B'):pack(self.timesig))
    end
  else
    assert(version == 3)
    f:write(('H'):pack(self.length))
    f:write(('B'):pack(self.loop))
    f:write(('B'):pack(self.timesig))
    f:write(('B'):pack(self.tempo))
    for _, v in ipairs(self.songdata) do
      f:write(('B'):pack(v))
    end
  end
end

-- return module
return {
  new = new,
  read = read,
}
