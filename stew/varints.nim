## This module implements Variable Integer `VARINT`.

import
  bitops2

type
  VarintFlavour* = enum
    ProtoBuf
    LibP2P

  VarintState* {.pure.} = enum
    Incomplete,
    Done,
    Overflow

  VarintParser*[IntType; flavour: static VarintFlavour] = object
    ## This stateful object can be used to parse varints.
    ##
    ## Type parameters:
    ##
    ##  * `IntType` - The output type the parser will try to read
    ##  * `flavour` - The type of varint encoding.
    ##
    ## The following encodings are supported:
    ##
    ##  * `ProtoBuf`
    ##
    ##    The encoding used by Google ProtoBuf.
    ##    It's able to encode a full uint64 number and the maximum
    ##    encoded size is 10 octets (bytes).
    ##
    ##    When decoding 10th byte of Google Protobuf's 64bit integer
    ##    only 1 bit from byte will be decoded, all other bits will
    ##    be ignored. When decoding 5th byte of 32bit integer only
    ##    4 bits from byte will be decoded, all other bits will be
    ##    ignored.
    ##
    ##  * `LibP2P`
    ##
    ##    Encoding used by the LibP2P project.
    ##    It ca encode only lower 63 bits of a uint64 number with a
    ##    maximum size for the encoded value of 9 octets (bytes).
    ##
    ##    When decoding 5th byte of 32bit integer only 4 bits from
    ##    byte will be decoded, all other bits will be ignored.
    ##
    ## Usage protocol:
    ##
    ## This object is initialized with the default zero-initialization.
    ## Proceed to calling `feedByte` one or multiple times and then obtain
    ## the result with `getResult`.
    ##
    shift: uint8
    when IntType is int64|uint64:
      res: uint64
    else:
      res: uint32
    when defined(debug):
      state: VarintState

func maxBits(T: type VarintParser): uint8 {.compileTime.} =
  when T.flavour == ProtoBuf:
    uint8(sizeof(T.IntType) * 8)
  elif sizeof(T.IntType) == 8:
    uint8(63)
  else:
    uint(sizeof(T.IntType) * 8)

func feedByte*(p: var VarintParser, b: byte): VarintState =
  ## Supplies the next input byte to the varint parser.
  ## The return value is one of the following:
  ##
  ##  * `Incomplete`
  ##     More input bytes must be supplied.
  ##
  ##  * `Done`
  ##     The varint has been read to completion.
  ##     Use `parser.getResult` to obtain it.
  ##
  ##  * `Overflow`
  ##     The maximum number of bits in the parser output value
  ##     has been exceed. The supplied input can be considered invalid.
  ##
  const maxShift = maxBits type(p)

  if p.shift >= maxShift:
    return Overflow

  p.res = p.res or (uint64(b and 0x7F'u8) shl p.shift)
  p.shift += 7

  if (b and 0x80'u8) == 0'u8:
    when defined(debug): p.state = Done
    Done
  else:
    Incomplete

func getResult*[IntType, F](p: VarintParser[IntType, F]): IntType {.inline.} =
  ## Returns the final result of the varint parsing.
  ## This function must be called after a previous call to `parser.feedByte`
  ## has returned the state `Done`. The result of calling the function at
  ## any other time is undefined.
  when defined(debug):
    doAssert p.state == Done

  when result is SomeSignedInt:
    type UIntType = type(p.res)

    if p.res and UIntType(1) != UIntType(0):
      cast[p.IntType](not (p.res shr 1))
    else:
      cast[p.IntType](p.res shr 1)
  else:
    p.res

func readVarint*(input: openarray[byte],
                 outVal: var SomeInteger,
                 flavour: static VarintFlavour = ProtoBuf): int =
  ## Reads a varint from a buffer and stores it in `outVal`.
  ## The return value indicates the number of bytes read.
  ## If the buffer doesn't hold a valid varint value, the
  ## function will return 0.
  var
    parser: VarintParser[type(outVal), flavour]
    pos = 0

  while pos < input.len:
    case parser.feedByte(input[pos])
    of Incomplete:
      inc pos
    of Done:
      outVal = parser.getResult
      return pos + 1
    of Overflow:
      return 0

func readVarint*[Stream](input: var Stream,
                         T: type SomeInteger,
                         flavour: static VarintFlavour = ProtoBuf): T =
  ## Reads a varint from a stream (e.g. fastreams.InputStream) and returns it.
  ##
  ## The following exceptions may be raised:
  ##
  ## * `EOFError`
  ##   The end of the stream was reached before the varint
  ##   was completely read.
  ##
  ## * `ValueError`
  ##   The stream contained an invalid varint value.
  var parser: VarintParser[T, flavour]

  while not input.eof:
    case parser.feedByte(input.read)
    of Done:
      return parser.getResult
    of Overflow:
      raise newException(ValueError, "Failed to read a varint")
    of Incomplete:
      continue

  raise newException(EOFError, "Failed to read a varint")

func appendVarintImpl[Stream](s: var Stream, x: SomeUnsignedInt) {.inline.} =
  mixin append
  type UInt = type(x)

  if x <= 0x7F:
    s.append byte(x and 0xFF)
  else:
    var x = x
    while true:
      var nextByte = byte((x and 0x7F) or 0x80)
      x = x shr 7
      if x == 0:
        nextByte = nextByte and 0x7F
        s.append nextByte
        return
      else:
        s.append nextByte

func appendVarint*[Stream](s: var Stream, x: SomeInteger,
                           flavour: static VarintFlavour = ProtoBuf) {.inline.} =
  ## Writes a varint to a stream (e.g. faststreams.OutputStream)
  when x is SomeSignedInt:
    type UInt = (when sizeof(x) == 8: uint64
                 elif sizeof(x) == 4: uint32
                 else: uint16)

    let x = if x < 0: not(cast[UInt](x) shl 1)
            else: cast[UInt](x) shl 1

  when flavour == LibP2P and sizeof(x) == 8:
    doAssert(x.getBitBE(0) == false)

  s.appendVarintImpl x

func vsizeof*(x: SomeInteger): int {.inline.} =
  ## Returns number of bytes required to encode integer ``x`` as varint.
  if x == 0: 1
  else: (log2trunc(x) + 1 + 7 - 1) div 7

