import
  unittest, random,
  ../stew/[varints, byteutils]

const edgeValues = {
  0'u64                     : "00",
  (1'u64 shl 7) - 1'u64     : "7f",
  (1'u64 shl 7)             : "8001",
  (1'u64 shl 14) - 1'u64    : "ff7f",
  (1'u64 shl 14)            : "808001",
  (1'u64 shl 21) - 1'u64    : "ffff7f",
  (1'u64 shl 21)            : "80808001",
  (1'u64 shl 28) - 1'u64    : "ffffff7f",
  (1'u64 shl 28)            : "8080808001",
  (1'u64 shl 35) - 1'u64    : "ffffffff7f",
  (1'u64 shl 35)            : "808080808001",
  (1'u64 shl 42) - 1'u64    : "ffffffffff7f",
  (1'u64 shl 42)            : "80808080808001",
  (1'u64 shl 49) - 1'u64    : "ffffffffffff7f",
  (1'u64 shl 49)            : "8080808080808001",
  (1'u64 shl 56) - 1'u64    : "ffffffffffffff7f",
  (1'u64 shl 56)            : "808080808080808001",
  (1'u64 shl 63) - 1'u64    : "ffffffffffffffff7f",
  uint64(1'u64 shl 63)      : "80808080808080808001",
  0xFFFF_FFFF_FFFF_FFFF'u64 : "ffffffffffffffffff01"
}

type
  PseudoStream = object
    bytes: array[12, byte]
    bytesWritten: int

func append(s: var PseudoStream, b: byte) =
  s.bytes[s.bytesWritten] = b
  inc s.bytesWritten

template writtenData(s: PseudoStream): auto =
  s.bytes.toOpenArray(0, s.bytesWritten - 1)

suite "varints":
  template roundtipTest(val) =
    var s {.inject.}: PseudoStream
    s.appendVarint val

    var roundtripVal: uint64
    let bytesRead = readVarint(s.bytes, roundtripVal)

    check:
      val == roundtripVal
      bytesRead == s.bytesWritten
      bytesRead == vsizeof(val)

  test "[ProtoBuf] Success edge cases test":
    for pair in edgeValues:
      let (val, hex) = pair
      roundtipTest val
      check:
        s.bytesWritten == hex.len div 2
        toHex(s.writtenData) == hex

  test "[ProtoBuf] random values":
      for i in 0..10000:
        let val = rand(0'u64 .. 0xFFFF_FFFF_FFFF_FFFE'u64)
        roundtipTest val

  # TODO Migrate the rest of the LibP2P test cases
