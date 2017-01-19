-- pandatracker file format
--
-- thanks to
-- - setrodox for writing the tracker in the first place
-- - slimeball for reverse engineering for it2panda
--
-- header:
-- $00 8 STRING literal 'PANDADEV'
-- $08 3 n/a    padding?
-- $0B 1 BYTE   version?
-- $0C 4 UINT   file size left to read
-- $10 1 BYTE   compression byte (see "compression")
-- $11 1 UINT   red GUI color multiplier
-- $12 1 UINT   green GUI color multiplier
-- $13 1 UINT   blue GUI color multiplier
-- $14 1 UINT   speed ($01-$0F, lower is faster)
--
-- order list:
-- $15 ? []BYTE compressed order data, $40 bytes uncompressed
--              see ("compression")
--
-- pattern data:
-- $?? ? []BYTE compressed pattern data (see "compression")
--              read by columns! for RLE, presumably (TODO)
--
-- compression:
-- pandatracker uses a type of RLE to compress order and pattern data.
-- if a byte is encountered equal to the compression byte from the header,
-- the next byte TODO

SIGNATURE = 'PANDADEV'  -- begins a .panda file

-- return n bytes decoded from a decoder
-- decoder must have elements 'f', 'filepos', 'buf', and 'compbyte'
local function decode(dec, n)
  while #dec.buf < n do
    local byte = dec.f:read(1)
    dec.filepos = dec.filepos + 1
    if ('B'):unpack(byte) == dec.compbyte then
      local len = 0
      for i = 0, 1 do
        local lenbyte = ('B'):unpack(dec.f:read(1))
        dec.filepos = dec.filepos + 1
        if i == 1 then
          len = (len << 8) + lenbyte
        else
          len = lenbyte & 0x7F
        end
        if lenbyte & 0x80 == 0 then break end
      end
      fill = dec.f:read(1)
      dec.filepos = dec.filepos + 1
      for i = 1, len+1 do
        dec.buf = dec.buf .. fill
      end
    else
      dec.buf = dec.buf .. byte
    end
  end
  local bytes = dec.buf:sub(1, n)
  dec.buf = dec.buf:sub(n+1)
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
    patterns={},
  }
  local filesize = ('I'):unpack(f:read(4)) + 0x10
  pandafile.compbyte = ('B'):unpack(f:read(1))
  pandafile.red, pandafile.green, pandafile.blue = ('BBB'):unpack(f:read(3))
  pandafile.speed = ('B'):unpack(f:read(1))

  --- order list
  local dec = { f=f, filepos=0x15, buf='', compbyte=pandafile.compbyte }
  for i = 1, 64 do
    local order = ('B'):unpack(decode(dec, 1))
    pandafile.orders[i] = order
  end

  -- pattern data
  for i = 1, 64 do
    pandafile.patterns[i] = {}
  end
  for ncol = 1, 32 do
    for npat, pattern in ipairs(pandafile.patterns) do
      local column = {}
      for nrow = 1, 64 do
        column[nrow] = ('B'):unpack(decode(dec, 1))
      end
      pattern[ncol] = column
    end
  end
  assert(dec.filepos == filesize)

  f:close()
  return pandafile, nil
end

-- test code
-- local pandafile, err = read(arg[1])
-- if err ~= nil then error(err) end
