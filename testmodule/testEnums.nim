import std/os
import pkg/asynctest/chronos/unittest
import pkg/ethers
import pkg/serde
import ./hardhat

type
  TestEnums = ref object of Contract
  SomeEnum = enum
    One
    Two

suite "Contract enum parameters and return values":

  var contract: TestEnums
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  let url = "http://" & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")

  setup:
    provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
    snapshot = await provider.send("evm_snapshot")
    let deployment = readDeployment()
    contract = TestEnums.new(!deployment.address(TestEnums), provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "handles enum parameter and return value":
    proc returnValue(contract: TestEnums,
                     value: SomeEnum): SomeEnum {.contract, pure.}
    check (await contract.returnValue(SomeEnum.One)) == SomeEnum.One
    check (await contract.returnValue(SomeEnum.Two)) == SomeEnum.Two
