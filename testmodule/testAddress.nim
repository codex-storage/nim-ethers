import std/unittest
import pkg/ethers/address
import pkg/questionable

suite "Address":

  let address = Address.init [
    0x1'u8, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa,
    0x1   , 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa
  ]

  test "can be converted to string":
    check $address == "0x0102030405060708090a0102030405060708090a"

  test "can be parsed from string":
    check:
      Address.init("0x0102030405060708090a0102030405060708090a") == some address

  test "parsing fails when string does not contain proper hex":
    check:
      Address.init("0xfoo2030405060708090a0102030405060708090a") == none Address

  test "parsing fails when string does not contain 20 bytes":
    check:
      Address.init("0x0102030405060708090a010203040506070809") == none Address
