-- shroomplayer sho file format
--
-- common data:
-- $000 4   STRING literal "shro"
-- $004 1   BYTE   sho version
-- $005 2   n/a    reserved
-- $007 32  STRING title
-- $027 32  STRING author
-- $047 32  STRING shi filename (sample pack), default "default.shi"
--
-- if version is $01 (shroomplayer) or $02 (mariopants):
-- $067 576 []BYTE song data (see "song data format")
-- $2A7 1   UINT   tempo ($00-$9F)
--
-- if version is $02 (mariopants):
-- $2A8 1   UINT   song length in beats ($01-$60)
-- $2A9 1   BOOL   song loop flag
-- $2AA 1   BOOL   time signature ($00 = 3/4, $01 = 4/4)
--
-- if version is $03 (mariopants extended):
-- $067 2   UINT   song length in beats ($0061-$0B40)
-- $069 1   BOOL   song loop flag
-- $06A 1   BOOL   time signature ($00 = 3/4, nz $01 = 4/4)
-- $06B 1   UINT   tempo ($00-$9F)
-- $05C ?   []BYTE song data (see "song data structure")
--      ^ length = song length * 6
--
-- song data structure; beat/channel array in beat-major order w/ 3 channels:
-- +0   1   BYTE   pitch ($01-$0D = pitch, $FF = off)
-- +1   1   BYTE   instrument ($00-$0E = instrument, $DF = off)

local SIGNATURE = 'shro'  -- begins a .sho file
local SHIFILE_DEFAULT = 'default.shi'

-- returns shofile, error
local function read(path)
  local f, err = io.open(path, 'rb')
  if err then return nil, err end

  -- check signature and version validity
  if f:read(4) ~= SIGNATURE then return nil, 'not a sho file' end
  local version = ('B'):unpack(f:read(1))
  if version < 1 or version > 3 then return nil, 'unsupported sho version' end
  f:seek("cur", 2)

  -- common stuff
  local shofile = {
    version=version,
    title=f:read(32):gsub('\0', ''),
    author=f:read(32):gsub('\0', ''),
    shifile=f:read(32):gsub('\0', ''),
    songdata={},
  }

  -- version-specific stuff
  if version == 1 or version == 2 then
    for i = 1, 576 do
      shofile.songdata[i] = ('b'):unpack(f:read(1))
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
      shofile.songdata[i] = ('b'):unpack(f:read(1))
    end
  end

  f:close()
  return shofile, nil
end

-- returns error
local function write(shofile, path)
  local f, err = io.open(path, 'wb')
  if err then return err end

  -- TODO

  f:close()
  return nil
end

-- local shofile, err = read(arg[1])
-- if err ~= nil then error(err) end
