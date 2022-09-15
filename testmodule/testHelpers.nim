import std/json
import std/strformat
import pkg/asynctest
import pkg/chronos
import pkg/ethers
import ./hardhat
import ./helpers

suite "Revert helpers":

  let revertReason = "revert reason"
  let rpcResponse = %* {
    "message": "Error: VM Exception while processing transaction: " &
               fmt"reverted with reason string '{revertReason}'"
  }

  test "can use block syntax async":
    let ethCallAsync = proc() {.async.} =
      raise newException(EthersError, $rpcResponse)

    check:
      reverts:
        await ethCallAsync()

  test "can use block syntax sync":
    let ethCall = proc() =
      raise newException(EthersError, $rpcResponse)

    check:
      reverts:
        ethCall()

  test "can use parameter syntax async":
    let ethCallAsync = proc() {.async.} =
      raise newException(EthersError, $rpcResponse)

    check:
      reverts (await ethCallAsync())

  test "can use parameter syntax sync":
    let ethCall = proc() =
      raise newException(EthersError, $rpcResponse)

    check:
      reverts ethCall()

  test "successfully checks revert reason async":
    let ethCallAsync = proc() {.async.} =
      raise newException(EthersError, $rpcResponse)

    check:
      revertsWith revertReason:
        await ethCallAsync()

  test "successfully checks revert reason sync":
    let ethCall = proc() =
      raise newException(EthersError, $rpcResponse)

    check:
      revertsWith revertReason:
        ethCall()


  test "correctly indicates there was no revert":
    let ethCall = proc() = discard

    check:
      doesNotRevert:
        ethCall()

  test "only checks EthersErrors":
    let ethCall = proc() =
      raise newException(ValueError, $rpcResponse)

    check:
      doesNotRevert:
        ethCall()

  test "revertsWith is false when there is no revert":
    let ethCall = proc() = discard

    check:
      doesNotRevertWith revertReason:
        ethCall()

  test "revertsWith is false when not an EthersError":
    let ethCall = proc() =
      raise newException(ValueError, $rpcResponse)

    check:
      doesNotRevertWith revertReason:
        ethCall()

  test "revertsWith is false when the revert reason doesn't match":
    let ethCall = proc() =
      raise newException(EthersError, "other reason")

    check:
      doesNotRevertWith revertReason:
        ethCall()

  test "revertsWith handles non-standard revert prefix":
    let nonStdMsg = fmt"Provider VM Exception: reverted with {revertReason}"
    let nonStdRpcResponse = %* { "message": nonStdMsg }
    let ethCall = proc() =
      raise newException(EthersError, $nonStdRpcResponse)

    check:
      revertsWith nonStdMsg:
        ethCall()

type
  TestHelpers* = ref object of Contract

method revertsWith*(self: TestHelpers,
                    revertReason: string) {.base, contract, view.}

suite "Revert helpers - current provider":

  var helpersContract: TestHelpers
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  var accounts: seq[Address]
  let revertReason = "revert reason"

  setup:
    provider = JsonRpcProvider.new("ws://127.0.0.1:8545")
    snapshot = await provider.send("evm_snapshot")
    accounts = await provider.listAccounts()
    let deployment = readDeployment()
    helpersContract = TestHelpers.new(!deployment.address(TestHelpers), provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])

  test "revert prefix is emitted from current provider":
    check:
      revertsWith revertReason:
        await helpersContract.revertsWith(revertReason)




