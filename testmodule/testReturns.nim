import std/os
import pkg/asynctest/chronos/unittest
import pkg/ethers
import pkg/serde
import ./hardhat

type
  TestReturns = ref object of Contract
  Static = (UInt256, UInt256)
  Dynamic = (string, UInt256)

suite "Contract return values":

  var contract: TestReturns
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  let url = "http://" & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")

  setup:
    provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
    snapshot = await provider.send("evm_snapshot")
    let deployment = readDeployment()
    contract = TestReturns.new(!deployment.address(TestReturns), provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "handles static size structs":
    proc getStatic(contract: TestReturns): Static {.contract, pure.}
    proc getStatics(contract: TestReturns): (Static, Static) {.contract, pure.}
    check (await contract.getStatic()) == (1.u256, 2.u256)
    check (await contract.getStatics()) == ((1.u256, 2.u256), (3.u256, 4.u256))

  test "handles dynamic size structs":
    proc getDynamic(contract: TestReturns): Dynamic {.contract, pure.}
    proc getDynamics(contract: TestReturns): (Dynamic, Dynamic) {.contract, pure.}
    check (await contract.getDynamic()) == ("1", 2.u256)
    check (await contract.getDynamics()) == (("1", 2.u256), ("3", 4.u256))

  test "handles mixed dynamic and static size structs":
    proc getDynamicAndStatic(contract: TestReturns): (Dynamic, Static) {.contract, pure.}
    check (await contract.getDynamicAndStatic()) == (("1", 2.u256), (3.u256, 4.u256))

  test "handles return type that is a tuple with a single element":
    proc getDynamic(contract: TestReturns): (Dynamic,) {.contract, pure.}
    check (await contract.getDynamic()) == (("1", 2.u256),)

  test "handles parentheses around return type":
    proc getDynamic(contract: TestReturns): (Dynamic) {.contract, pure.}
    check (await contract.getDynamic()) == ("1", 2.u256)

  test "handles return type that is an explicit tuple":
    proc getDynamics(contract: TestReturns): tuple[a, b: Dynamic] {.contract, pure.}
    let values = await contract.getDynamics()
    check values.a == ("1", 2.u256)
    check values.b == ("3", 4.u256)

  test "handles static size struct as a public state variable":
    proc staticVariable(contract: TestReturns): Static {.contract, getter.}
    check (await contract.staticVariable()) == (1.u256, 2.u256)

  test "handles dynamic size struct as a public state variable":
    proc dynamicVariable(contract: TestReturns): Dynamic {.contract, getter.}
    check (await contract.dynamicVariable()) == ("3", 4.u256)
