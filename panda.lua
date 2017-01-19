-- pandatracker file format (for version pre8)
--
-- thanks to
-- - setrodox for writing the tracker in the first place
-- - slimeball for reverse engineering for it2panda
--
-- header:
-- $00 [9]byte   literal 'PANDADEV'
-- $08 [3]byte   unused?
-- $0B byte      unknown, $02 in all the modules i could find
-- $0C uint32    file size left to read
-- $10 byte      compression byte (see "compression")
-- $11 uint8     red GUI color multiplier
-- $12 uint8     green GUI color multiplier
-- $13 uint8     blue GUI color multiplier
-- $14 uint8     speed ($01-$0F, lower is faster)
--
-- everything beyond this point is compressed (see below).
-- when uncompressed, it looks like this:
--
-- order list:
-- $15 [64]uint8 order list ($00-$3F, $FF = none)
--
-- pattern data:
-- $55 [8]array  channel (1->8)
--  of [4]array  column (note->volume->effect->param)
--  of [64]array pattern (0->63)
--  of [64]byte  row:
--               note ($03-$C2, $00 = none) or
--               volume ($10-$50, $00 = none) or
--               effect (unused) or
--               param (unused)
--
-- a form of RLE is used for order list and pattern data compression. if a byte
-- A read from the file is equal to the compression byte defined in the header,
-- the next byte B denotes the length of the run, unless the high bit of B is
-- set, in which case the length equals the low 15 bits of BC (little-endian),
-- where C is the next byte. the decoded chunk is equal to the next byte,
-- length+1 times in a row. if byte A is not equal to the compression byte, it
-- is read as usual. example if compression byte is 7:
--
-- 01 02 07 03 07 07 81 80 FF -> 01 02 07 07 07 FF FF .. (380 more) .. FF FF

SIGNATURE = 'PANDADEV'  -- begins a .panda file

-- decode the next chunk, returning length, byte, and count of bytes read
local function decoderun(f, compbyte)
  local length, byte, count = 1, f:read(1), 1
  if byte == compbyte then
    local lenbyte = ('B'):unpack(f:read(1))
    length = lenbyte & 0x7F
    if lenbyte & 0x80 ~= 0 then
      length = (length << 8) + ('B'):unpack(f:read(1))
      count = count + 1
    end
    length, byte, count = length + 1, f:read(1), count + 2
  end
  assert(byte ~= nil)
  return length, byte, count
end

-- return n bytes decoded from a decoder
local function decode(dec, n)
  while #dec.buf < n + dec.off do
    local length, byte, count = decoderun(dec.f, dec.compbyte)
    dec.filepos = dec.filepos + count
    for i = 1, length do
      table.insert(dec.buf, byte)
    end
  end
  local bytes = table.concat(dec.buf, '', dec.off + 1, dec.off + n)
  dec.off = dec.off + n
  return bytes
end

-- returns pandafile, error
local function read(path)
  local f, err = io.open(path, 'rb')
  if err then return nil, err end

  -- check signature validity
  if f:read(8) ~= SIGNATURE then return nil, 'not a panda file' end

  -- header
  local pandafile = {
    version=('xxxB'):unpack(f:read(4)),
    orders={},
    channels={},
  }
  local filesize = ('I'):unpack(f:read(4)) + 0x10
  pandafile.compbyte = f:read(1)
  pandafile.red, pandafile.green, pandafile.blue = ('BBB'):unpack(f:read(3))
  pandafile.speed = ('B'):unpack(f:read(1))

  --- order list
  local dec = { f=f, filepos=0x15, buf={}, compbyte=pandafile.compbyte, off=0 }
  for i = 1, 64 do
    local order = ('B'):unpack(decode(dec, 1))
    pandafile.orders[i] = order
  end

  -- pattern data
  for nchan = 1, 8 do
    local channel = {}
    for ncol = 1, 4 do
      local column = {}
      for npat = 1, 64 do
        local pattern = {}
        for nrow = 1, 64 do
          pattern[nrow] = ('B'):unpack(decode(dec, 1))
        end
        column[npat] = pattern
      end
      channel[ncol] = column
    end
    pandafile.channels[nchan] = channel
  end
  assert(dec.filepos == filesize)

  f:close()
  return pandafile, nil
end

-- return the (possibly) compressed byte string encoding of the given run
local function encoderun(compbyte, length, byte)
  local chunk = ''

  if length < 4 and byte ~= ('B'):unpack(compbyte) then
    -- write uncompressed
    for i = 1, length do
      chunk = chunk .. ('B'):pack(byte)
    end
  elseif length < 0x80 then
    -- compress into 3 bytes
    chunk = compbyte .. ('BB'):pack(length - 1, byte)
  else
    -- compress into 4 bytes
    assert(length < 0x8000)
    length = length - 1
    chunk = compbyte .. ('BBB'):pack(0x80 | (length >> 8), length & 0xFF, byte)
  end

  return chunk
end

-- write a byte to the encoder. pass nill to flush
local function encode(enc, byte)
  if enc.length < 0x7FFF and (byte == enc.byte or enc.length == 0) then
    enc.length, enc.byte = enc.length + 1, byte
  else
    table.insert(enc.chunks, encoderun(enc.compbyte, enc.length, enc.byte))
    enc.length, enc.byte = 1, byte
  end
end

-- returns error
local function write(pandafile, path)
  local f, err = io.open(path, 'wb')
  if err then return err end

  -- have to compress data first so that we know the file size
  local enc = { chunks={}, compbyte=pandafile.compbyte, length=0, byte=nil }
  for _, order in ipairs(pandafile.orders) do
    encode(enc, order)
  end
  for _, channel in ipairs(pandafile.channels) do
    for _, column in ipairs(channel) do
      for _, pattern in ipairs(column) do
        for _, row in ipairs(pattern) do
          encode(enc, row)
        end
      end
    end
  end
  encode(enc, nil)  -- flush buffered data
  local compdata = table.concat(enc.chunks)

  -- then write everything
  f:write(SIGNATURE)
  f:write(('xxxBIc1BBBB'):pack(pandafile.version, #compdata + 0x05,
    pandafile.compbyte, pandafile.red, pandafile.green, pandafile.blue,
    pandafile.speed))
  f:write(compdata)

  f:close()
  return nil
end

-- local pandafile, err = read(arg[1])
-- if err ~= nil then error(err) end
-- err = write(pandafile, arg[2])
-- if err ~= nil then error(err) end
