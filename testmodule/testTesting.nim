import std/os
import std/strformat
import pkg/asynctest/chronos/unittest
import pkg/chronos
import pkg/ethers
import pkg/ethers/testing
import pkg/serde
import ./helpers

suite "Testing helpers":

  let revertReason = "revert reason"
  let rpcResponse = "Error: VM Exception while processing transaction: " &
                    fmt"reverted with reason string '{revertReason}'"

  test "checks that call reverts":
    proc call() {.async.} =
      raise newException(EstimateGasError, $rpcResponse)

    check await call().reverts()

  test "checks reason for revert":
    proc call() {.async.} =
      raise newException(EstimateGasError, $rpcResponse)

    check await call().reverts(revertReason)

  test "correctly indicates there was no revert":
    proc call() {.async.} = discard

    check not await call().reverts()

  test "reverts only checks ProviderErrors, EstimateGasErrors":
    proc callProviderError() {.async.} =
      raise newException(ProviderError, "test")
    proc callSignerError() {.async.} =
      raise newException(SignerError, "test")
    proc callEstimateGasError() {.async.} =
      raise newException(EstimateGasError, "test")
    proc callEthersError() {.async.} =
      raise newException(EthersError, "test")

    check await callProviderError().reverts()
    check await callSignerError().reverts()
    check await callEstimateGasError().reverts()
    expect EthersError:
      check await callEthersError().reverts()

  test "reverts with reason only checks ProviderErrors, EstimateGasErrors":
    proc callProviderError() {.async.} =
      raise newException(ProviderError, revertReason)
    proc callSignerError() {.async.} =
      raise newException(SignerError, revertReason)
    proc callEstimateGasError() {.async.} =
      raise newException(EstimateGasError, revertReason)
    proc callEthersError() {.async.} =
      raise newException(EthersError, revertReason)

    check await callProviderError().reverts(revertReason)
    check await callSignerError().reverts(revertReason)
    check await callEstimateGasError().reverts(revertReason)
    expect EthersError:
      check await callEthersError().reverts(revertReason)

  test "reverts with reason is false when there is no revert":
    proc call() {.async.} = discard

    check not await call().reverts(revertReason)

  test "reverts is false when the revert reason doesn't match":
    proc call() {.async.} =
      raise newException(EstimateGasError, "other reason")

    check not await call().reverts(revertReason)

  test "revert handles non-standard revert prefix":
    let nonStdMsg = fmt"Provider VM Exception: reverted with {revertReason}"
    proc call() {.async.} =
      raise newException(EstimateGasError, nonStdMsg)

    check await call().reverts(nonStdMsg)

  test "works with functions that return a value":
    proc call(): Future[int] {.async.} = return 42
    check not await call().reverts()
    check not await call().reverts(revertReason)


suite "Testing helpers - contracts":

  var helpersContract: TestHelpers
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  var accounts: seq[Address]
  let revertReason = "revert reason"
  let url = "ws://" & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")

  setup:
    provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
    snapshot = await provider.send("evm_snapshot")
    accounts = await provider.listAccounts()
    helpersContract = TestHelpers.new(provider.getSigner())

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "revert reason can be retrieved when transaction fails":
    let txResp = helpersContract.doRevert(
                  revertReason,
                  # override gasLimit to skip estimating gas
                  TransactionOverrides(gasLimit: some 10000000.u256)
                )
    check await txResp.confirm(1).reverts(revertReason)

  test "revert reason can be retrieved when estimate gas fails":
    let txResp = helpersContract.doRevert(revertReason)
    check await txResp.reverts(revertReason)
