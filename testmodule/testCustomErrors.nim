import std/json
import pkg/asynctest
import pkg/ethers
import ./hardhat

suite "Contract custom errors":

  type
    TestCustomErrors = ref object of Contract
    SimpleError = object of SolidityError

  var contract: TestCustomErrors
  var provider: JsonRpcProvider
  var snapshot: JsonNode

  setup:
    provider = JsonRpcProvider.new()
    snapshot = await provider.send("evm_snapshot")
    let deployment = readDeployment()
    let address = !deployment.address(TestCustomErrors)
    contract = TestCustomErrors.new(address, provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "handles simple errors":
    proc revertsSimpleError(contract: TestCustomErrors)
      {.contract, pure, errors:[SimpleError].}

    expect SimpleError:
      await contract.revertsSimpleError()
