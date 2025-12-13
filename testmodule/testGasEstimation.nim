import std/os
import pkg/asynctest/chronos/unittest
import pkg/ethers
import pkg/serde
import ./hardhat

type
  TestGasEstimation = ref object of Contract

proc getTime(contract: TestGasEstimation): UInt256 {.contract, view.}
proc checkTimeEquals(contract: TestGasEstimation, expected: UInt256) {.contract.}

suite "gas estimation":

  var contract: TestGasEstimation
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  let url = "http://" & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")

  setup:
    provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
    snapshot = await provider.send("evm_snapshot")
    let deployment = readDeployment()
    let signer = provider.getSigner()
    contract = TestGasEstimation.new(!deployment.address(TestGasEstimation), signer)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "contract function calls use pending block for gas estimations":
    let latest = CallOverrides(blockTag: some BlockTag.latest)
    let pending = CallOverrides(blockTag: some BlockTag.pending)

    # retrieve time of pending block
    let time = await contract.getTime(overrides=pending)

    # ensure that time of latest block and pending block differ
    check (await contract.getTime(overrides=latest)) != time

    # only succeeds when gas estimation is done using the pending block,
    # otherwise it will fail with "Transaction ran out of gas"
    await contract.checkTimeEquals(time)

  test "contract gas estimation uses pending block":
    let latest = CallOverrides(blockTag: some BlockTag.latest)
    let pending = CallOverrides(blockTag: some BlockTag.pending)

    # retrieve time of pending block
    let time = await contract.getTime(overrides=pending)

    # ensure that time of latest block and pending block differ
    check (await contract.getTime(overrides=latest)) != time

    # estimate gas
    let gas = await contract.estimateGas.checkTimeEquals(time)
    let overrides = TransactionOverrides(gasLimit: some gas)

    # only succeeds when gas estimation is done using the pending block,
    # otherwise it will fail with "Transaction ran out of gas"
    await contract.checkTimeEquals(time, overrides)

  test "contract gas estimation honors a block tag override":
    let latest = CallOverrides(blockTag: some BlockTag.latest)
    let pending = CallOverrides(blockTag: some BlockTag.pending)

    # retrieve time of pending block
    let time = await contract.getTime(overrides=pending)

    # ensure that time of latest block and pending block differ
    check (await contract.getTime(overrides=latest)) != time

    # estimate gas
    let gasLatest = await contract.estimateGas.checkTimeEquals(time, latest)
    let gasPending = await contract.estimateGas.checkTimeEquals(time, pending)

    check gasLatest != gasPending
