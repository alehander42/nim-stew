# byteutils
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest,
        ../stew/byteutils

suite "Byte utils":
  let simpleBArray = [0x12.byte, 0x34, 0x56, 0x78]

  test "hexToByteArray: Inplace partial string":
    let s = "0x1234567890"
    var a: array[5, byte]
    hexToByteArray(s, a, 1, 3)
    check a == [0.byte, 0x34, 0x56, 0x78, 0]

  test "hexToByteArray: Inplace full string":
    let s = "0xffffffff"
    var a: array[4, byte]
    hexToByteArray(s, a)
    check a == [255.byte, 255, 255, 255]

  test "hexToByteArray: Return array":
    let
      s = "0x12345678"
      a = hexToByteArray[4](s)
    check a == simpleBArray

  test "toHex":
    check simpleBArray.toHex == "12345678"

  test "Array concatenation":
    check simpleBArray & simpleBArray ==
      [0x12.byte, 0x34, 0x56, 0x78, 0x12, 0x34, 0x56, 0x78]

  test "hexToPaddedByteArray":
    block:
      let a = hexToPaddedByteArray[4]("0x123")
      check a.toHex == "00000123"
    block:
      let a = hexToPaddedByteArray[4]("0x1234")
      check a.toHex == "00001234"
    block:
      let a = hexToPaddedByteArray[4]("0x1234567")
      check a.toHex == "01234567"
    block:
      let a = hexToPaddedByteArray[4]("0x12345678")
      check a.toHex == "12345678"
    block:
      let a = hexToPaddedByteArray[32]("0x68656c6c6f20776f726c64")
      check a.toHex == "00000000000000000000000000000000000000000068656c6c6f20776f726c64"
    block:
      expect AssertionError:
        let a = hexToPaddedByteArray[2]("0x12345")
