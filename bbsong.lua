-- beepola bbsong file format
--
-- this file format is documented in the online help.
-- it really likes to terminate things with null bytes.

local SIGNATURE = 'BBSONG\0'
local CHUNK_END = ':END'

local Song = {}
local Song_mt = { __index = Song }

-- most beepola strings are variable length and null-terminated
local function readstr(f)
  local str = {}
  while str[#str] ~= '\0' do
    str[#str+1] = f:read(1)
  end
  return table.concat(str, '', 1, #str-1)
end

-- read info chunk (general info about song)
local function readinfo(song, f)
  while true do
    local str = readstr(f)
    if str == CHUNK_END then
      break
    elseif str:find('Title=', 1, true) then
      song.title = str:sub(7)
    elseif str:find('Author=', 1, true) then
      song.author = str:sub(8)
    elseif str:find('Engine=', 1, true) then
      song.engine = str:sub(8)
    end
  end
end

local CHUNK_MAP = {}
CHUNK_MAP[':INFO'] = readinfo
-- the following chunks are not implemented for reading
-- ':LAYOUT' = readlayout,
-- ':PATTERNDATA' = readpatterndata,
-- ':P1INSRT' = readphaser,
-- ':SVGORNAMENTS' = readsvgornaments,
-- ':SVGPATTERNDATA' = readsvgpatterndata,
-- ':SVGWARPDATA' = readsvgwarpdata,
-- ';EXTPATTERNDATA' = readextpatterndata,

-- read a bbsong from a file. returns (song, err)
local function read(f)
  if f:read(7) ~= SIGNATURE then return nil, 'not a bbsong' end

  local song = { version = ('c4x'):unpack(f:read(5)) }

  while true do
    -- read a chunk (if we can identify it)
    local chunkstr = readstr(f)
    if chunkstr == '' then break end
    local readfunc = CHUNK_MAP[chunkstr]
    if readfunc ~= nil then
      readfunc(song, f)
    end
  end

  return setmetatable(song, Song_mt), nil
end

return {
  read = read,
}
