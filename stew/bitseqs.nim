import
  bitops2, endians2, ranges/ptr_arith

type
  Bytes = seq[byte]

  BitSeq* = distinct Bytes
    ## TODO
    ##
    ## The current design of BitSeq tries to follow precisely
    ## the bitwise representation of the SSZ bitlists.
    ## This is a relatively compact representation, but as
    ## evident from the code below, many of the operations
    ## are not trivial.
    ##
    ## An alternative simpler approach would be to maintain
    ## the BitSeq as a sequence of words with an external uint8
    ## counter denoting the used bits in the last word.
    ##
    ## This will reduce the complexity of the code here, but
    ## we'll have to define serialization routines for all the
    ## formats where such values appear (SSZ, JSON, YAML, etc).

  BitArray*[bits: static int] = object
    bytes*: array[(bits + 7) div 8, byte]

func len*(s: BitSeq): int =
  let
    bytesCount = s.Bytes.len
    lastByte = s.Bytes[bytesCount - 1]
    markerPos = log2trunc(lastByte)

  Bytes(s).len * 8 - (8 - markerPos)

template len*(a: BitArray): int =
  a.bits

func add*(s: var BitSeq, value: bool) =
  let
    lastBytePos = s.Bytes.len - 1
    lastByte = s.Bytes[lastBytePos]

  if (lastByte and byte(128)) == 0:
    # There is at least one leading zero, so we have enough
    # room to store the new bit
    let markerPos = log2trunc(lastByte)
    s.Bytes[lastBytePos].setBit markerPos, value
    s.Bytes[lastBytePos].raiseBit markerPos + 1
  else:
    s.Bytes[lastBytePos].setBit 7, value
    s.Bytes.add byte(1)

func loadLEBytes(WordType: type, bytes: openarray[byte]): WordType =
  # TODO: this is a temporary proc until the endians API is improved
  var shift = 0
  for b in bytes:
    result = result or (WordType(b) shl shift)
    shift += 8

func storeLEBytes(value: SomeUnsignedInt, dst: var openarray[byte]) =
  when system.cpuEndian == bigEndian:
    var shift = 0
    for i in 0 ..< dst.len:
      result[i] = byte((v shr shift) and 0xff)
      shift += 8
  else:
    copyMem(addr dst[0], unsafeAddr value, dst.len)

template loopOverWords(lhs, rhs: BitSeq,
                       lhsIsVar, rhsIsVar: static bool,
                       WordType: type,
                       lhsBits, rhsBits, body: untyped) =
  const hasRhs = astToStr(lhs) != astToStr(rhs)

  let bytesCount = len Bytes(lhs)
  when hasRhs: doAssert len(Bytes(rhs)) == bytesCount

  var fullWordsCount = bytesCount div sizeof(WordType)
  let lastWordSize = bytesCount mod sizeof(WordType)

  block:
    var lhsWord: WordType
    when hasRhs:
      var rhsWord: WordType
    var firstByteOfLastWord, lastByteOfLastWord: int

    # TODO: Returing a `var` value from an iterator is always safe due to
    # the way inlining works, but currently the compiler reports an error
    # when a local variable escapes. We have to cheat it with this location
    # obfuscation through pointers:
    template lhsBits: auto = (addr(lhsWord))[]

    when hasRhs:
      template rhsBits: auto = (addr(rhsWord))[]

    template lastWordBytes(bitseq): auto =
      Bytes(bitseq).toOpenArray(firstByteOfLastWord, lastByteOfLastWord)

    template initLastWords =
      lhsWord = loadLEBytes(WordType, lastWordBytes(lhs))
      when hasRhs: rhsWord = loadLEBytes(WordType, lastWordBytes(rhs))

    if lastWordSize == 0:
      firstByteOfLastWord = bytesCount - sizeof(WordType)
      lastByteOfLastWord  = bytesCount - 1
      dec fullWordsCount
    else:
      firstByteOfLastWord = bytesCount - lastWordSize
      lastByteOfLastWord  = bytesCount - 1

    initLastWords()
    let markerPos = log2trunc(lhsWord)
    when hasRhs: doAssert log2trunc(rhsWord) == markerPos

    lhsWord.lowerBit markerPos
    when hasRhs: rhsWord.lowerBit markerPos

    body

    when lhsIsVar or rhsIsVar:
      let
        markerBit = uint(1 shl markerPos)
        mask = markerBit - 1'u

      when lhsIsVar:
        let lhsEndResult = (lhsWord and mask) or markerBit
        storeLEBytes(lhsEndResult, lastWordBytes(lhs))

      when rhsIsVar:
        let rhsEndResult = (rhsWord and mask) or markerBit
        storeLEBytes(rhsEndResult, lastWordBytes(rhs))

  var lhsCurrAddr = cast[ptr WordType](unsafeAddr Bytes(lhs)[0])
  let lhsEndAddr = shift(lhsCurrAddr, fullWordsCount)
  when hasRhs:
    var rhsCurrAddr = cast[ptr WordType](unsafeAddr Bytes(rhs)[0])

  while lhsCurrAddr < lhsEndAddr:
    template lhsBits: auto = lhsCurrAddr[]
    when hasRhs:
      template rhsBits: auto = rhsCurrAddr[]

    body

    lhsCurrAddr = shift(lhsCurrAddr, 1)
    when hasRhs: rhsCurrAddr = shift(rhsCurrAddr, 1)

iterator words*(x: var BitSeq): var uint =
  loopOverWords(x, x, true, false, uint, word, wordB):
    yield word

iterator words*(x: BitSeq): uint =
  loopOverWords(x, x, false, false, uint, word, word):
    yield word

iterator words*(a, b: BitSeq): (uint, uint) =
  loopOverWords(a, b, false, false, uint, wordA, wordB):
    yield (wordA, wordB)

iterator words*(a: var BitSeq, b: BitSeq): (var uint, uint) =
  loopOverWords(a, b, true, false, uint, wordA, wordB):
    yield (wordA, wordB)

iterator words*(a, b: var BitSeq): (var uint, var uint) =
  loopOverWords(a, b, true, true, uint, wordA, wordB):
    yield (wordA, wordB)

func `[]`*(s: BitSeq, pos: Natural): bool {.inline.} =
  doAssert pos < s.len
  s.Bytes.getBit pos

func `[]=`*(s: var BitSeq, pos: Natural, value: bool) {.inline.} =
  doAssert pos < s.len
  s.Bytes.setBit pos, value

func raiseBit*(s: var BitSeq, pos: Natural) {.inline.} =
  doAssert pos < s.len
  raiseBit s.Bytes, pos

func lowerBit*(s: var BitSeq, pos: Natural) {.inline.} =
  doAssert pos < s.len
  lowerBit s.Bytes, pos

func init*(T: type BitSeq, len: int): T =
  result = BitSeq newSeq[byte](1 + len div 8)
  Bytes(result).raiseBit len

func init*(T: type BitArray): T =
  # The default zero-initializatio is fine
  discard

template `[]`*(a: BitArray, pos: Natural): bool =
  getBit a.bytes, pos

template `[]=`*(a: var BitArray, pos: Natural, value: bool) =
  setBit a.bytes, pos, value

template raiseBit*(a: var BitArray, pos: Natural) =
  raiseBit a.bytes, pos

template lowerBit*(a: var BitArray, pos: Natural) =
  lowerBit a.bytes, pos

# TODO: Submit this to the standard library as `cmp`
# At the moment, it doesn't work quite well because Nim selects
# the generic cmp[T] from the system module instead of choosing
# the openarray overload
func compareArrays[T](a, b: openarray[T]): int =
  result = cmp(a.len, b.len)
  if result != 0: return

  for i in 0 ..< a.len:
    result = cmp(a[i], b[i])
    if result != 0: return

template cmp*(a, b: BitSeq): int =
  compareArrays(Bytes a, Bytes b)

template `==`*(a, b: BitSeq): bool =
  cmp(a, b) == 0

func `$`*(a: BitSeq): string =
  let length = a.len
  result = newStringOfCap(2 + length)
  result.add "0b"
  for i in countdown(length - 1, 0):
    result.add if a[i]: '1' else: '0'

func combine*(tgt: var BitSeq, src: BitSeq) =
  doAssert tgt.len == src.len
  for tgtWord, srcWord in words(tgt, src):
    tgtWord = tgtWord or srcWord

func overlaps*(a, b: BitSeq): bool =
  for wa, wb in words(a, b):
    if (wa and wb) != 0:
      return true

func isSubsetOf*(a, b: BitSeq): bool =
  let alen = a.len
  doAssert b.len == alen
  for i in 0 ..< alen:
    if a[i] and not b[i]:
      return false
  true

proc isZeros*(x: BitSeq): bool =
  for w in words(x):
    if w != 0: return false
  return true

