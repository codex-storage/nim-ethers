import std/strformat
import pkg/asynctest
import pkg/chronos
import pkg/ethers
import pkg/ethers/testing
import ./hardhat

suite "Testing helpers":

  let revertReason = "revert reason"
  let rpcResponse = "Error: VM Exception while processing transaction: " &
                    fmt"reverted with reason string '{revertReason}'"

  test "checks that call reverts":
    proc call() {.async.} =
      raise newException(JsonRpcProviderError, $rpcResponse)

    check await call().reverts()

  test "checks reason for revert":
    proc call() {.async.} =
      raise newException(JsonRpcProviderError, $rpcResponse)

    check await call().reverts(revertReason)

  test "correctly indicates there was no revert":
    proc call() {.async.} = discard

    check not await call().reverts()

  test "reverts only checks JsonRpcProviderErrors":
    proc call() {.async.} =
      raise newException(ContractError, "test")

    expect ContractError:
      check await call().reverts()

  test "reverts with reason only checks JsonRpcProviderErrors":
    proc call() {.async.} =
      raise newException(ContractError, "test")

    expect ContractError:
      check await call().reverts(revertReason)

  test "reverts with reason is false when there is no revert":
    proc call() {.async.} = discard

    check not await call().reverts(revertReason)

  test "reverts is false when the revert reason doesn't match":
    proc call() {.async.} =
      raise newException(JsonRpcProviderError, "other reason")

    check not await call().reverts(revertReason)

  test "revert handles non-standard revert prefix":
    let nonStdMsg = fmt"Provider VM Exception: reverted with {revertReason}"
    proc call() {.async.} =
      raise newException(JsonRpcProviderError, nonStdMsg)

    check await call().reverts(nonStdMsg)

type
  TestHelpers* = ref object of Contract

method revertsWith*(self: TestHelpers,
                    revertReason: string) {.base, contract, view.}

suite "Testing helpers - provider":

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

  test "revert works with provider":
    check await helpersContract.revertsWith(revertReason).reverts(revertReason)
