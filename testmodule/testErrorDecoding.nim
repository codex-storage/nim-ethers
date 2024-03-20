import std/unittest
import pkg/questionable/results
import pkg/contractabi
import pkg/ethers/errors

suite "Decoding of custom errors":

  type
    SimpleError = object of SolidityError
    ErrorWithArguments = object of SolidityError
      arguments: tuple[one: UInt256, two: bool]

  test "decodes a simple error":
    let decoded = SimpleError.decode(@[0xc2'u8, 0xbb, 0x94, 0x7c])
    check decoded is ?!(ref SimpleError)
    check decoded.isSuccess
    check (!decoded) != nil

  test "decodes error with arguments":
    let expected = (ref ErrorWithArguments)(arguments: (1.u256, true))
    let encoded = AbiEncoder.encode(expected)
    let decoded = ErrorWithArguments.decode(encoded)
    check decoded.isSuccess
    check (!decoded).arguments.one == 1.u256
    check (!decoded).arguments.two == true

  test "returns failure when decoding fails":
    let invalid = @[0xc2'u8, 0xbb, 0x94, 0x0] # last byte is wrong
    let decoded = SimpleError.decode(invalid)
    check decoded.isFailure

  test "returns failure when data is less than 4 bytes":
    let invalid = @[0xc2'u8, 0xbb, 0x94]
    let decoded = SimpleError.decode(invalid)
    check decoded.isFailure

  test "decoding only works for SolidityErrors":
    type InvalidError = ref object of CatchableError
    const works = compiles:
      InvalidError.decode(@[0x1'u8, 0x2, 0x3, 0x4])
    check not works

