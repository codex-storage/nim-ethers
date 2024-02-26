import pkg/asynctest
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

  setup:
    provider = JsonRpcProvider.new()
    snapshot = await provider.send("evm_snapshot")
    let deployment = readDeployment()
    let signer = provider.getSigner()
    contract = TestGasEstimation.new(!deployment.address(TestGasEstimation), signer)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "uses pending block for gas estimations":
    let latest = CallOverrides(blockTag: some BlockTag.latest)
    let pending = CallOverrides(blockTag: some BlockTag.pending)

    # retrieve time of pending block
    let time = await contract.getTime(overrides=pending)

    # ensure that time of latest block and pending block differ
    check (await contract.getTime(overrides=latest)) != time

    # fails with "Transaction ran out of gas" when gas estimation
    # is not done using the pending block
    await contract.checkTimeEquals(time)
