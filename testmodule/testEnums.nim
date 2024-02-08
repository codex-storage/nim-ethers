import pkg/asynctest
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

  setup:
    provider = JsonRpcProvider.new()
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
