import std/unittest
import std/json
import pkg/questionable
import pkg/ethers/providers/jsonrpc/errors

suite "JSON RPC errors":

  test "converts JSON RPC error to Nim error":
    let error = %*{ "message": "some error" }
    check JsonRpcProviderError.new(error).msg == "some error"

  test "converts error data to bytes":
    let error = %*{
      "message": "VM Exception: reverted with 'some error'",
      "data": "0xabcd"
    }
    check JsonRpcProviderError.new(error).data == some @[0xab'u8, 0xcd'u8]

  test "converts nested error data to bytes":
    let error = %*{
      "message": "VM Exception: reverted with 'some error'",
      "data": {
        "message": "VM Exception: reverted with 'some error'",
        "data": "0xabcd"
      }
    }
    check JsonRpcProviderError.new(error).data == some @[0xab'u8, 0xcd'u8]
