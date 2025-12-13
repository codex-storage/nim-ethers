import std/os
import pkg/serde
import pkg/asynctest/chronos/unittest
import pkg/ethers
import ./hardhat

suite "Contract custom errors":

  type
    TestCustomErrors = ref object of Contract
    SimpleError = object of SolidityError
    ErrorWithArguments = object of SolidityError
      arguments: tuple[one: UInt256, two: bool]
    ErrorWithStaticStruct = object of SolidityError
      arguments: tuple[one: Static, two: Static]
    ErrorWithDynamicStruct = object of SolidityError
      arguments: tuple[one: Dynamic, two: Dynamic]
    ErrorWithDynamicAndStaticStruct = object of SolidityError
      arguments: tuple[one: Dynamic, two: Static]
    Static = (UInt256, UInt256)
    Dynamic = (string, UInt256)

  var contract: TestCustomErrors
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  let url = "http://" & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")

  setup:
    provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
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

  test "handles error with arguments":
    proc revertsErrorWithArguments(contract: TestCustomErrors)
      {.contract, pure, errors:[ErrorWithArguments].}

    try:
      await contract.revertsErrorWithArguments()
      fail()
    except ErrorWithArguments as error:
      check error.arguments.one == 1
      check error.arguments.two == true

  test "handles error with static struct arguments":
    proc revertsErrorWithStaticStruct(contract: TestCustomErrors)
      {.contract, pure, errors:[ErrorWithStaticStruct].}

    try:
      await contract.revertsErrorWithStaticStruct()
      fail()
    except ErrorWithStaticStruct as error:
      check error.arguments.one == (1.u256, 2.u256)
      check error.arguments.two == (3.u256, 4.u256)

  test "handles error with dynamic struct arguments":
    proc revertsErrorWithDynamicStruct(contract: TestCustomErrors)
      {.contract, pure, errors:[ErrorWithDynamicStruct].}

    try:
      await contract.revertsErrorWithDynamicStruct()
      fail()
    except ErrorWithDynamicStruct as error:
      check error.arguments.one == ("1", 2.u256)
      check error.arguments.two == ("3", 4.u256)

  test "handles error with dynamic and static struct arguments":
    proc revertsErrorWithDynamicAndStaticStruct(contract: TestCustomErrors)
      {.contract, pure, errors:[ErrorWithDynamicAndStaticStruct].}

    try:
      await contract.revertsErrorWithDynamicAndStaticStruct()
      fail()
    except ErrorWithDynamicAndStaticStruct as error:
      check error.arguments.one == ("1", 2.u256)
      check error.arguments.two == (3.u256, 4.u256)

  test "handles multiple error types":
    proc revertsMultipleErrors(contract: TestCustomErrors, simple: bool)
      {.contract, errors:[SimpleError, ErrorWithArguments].}

    let contract = contract.connect(provider.getSigner())
    expect SimpleError:
      await contract.revertsMultipleErrors(simple = true)
    expect ErrorWithArguments:
      await contract.revertsMultipleErrors(simple = false)

  test "handles gas estimation errors when calling a contract function":
    proc revertsTransaction(contract: TestCustomErrors)
      {.contract, errors:[ErrorWithArguments].}

    let contract = contract.connect(provider.getSigner())
    try:
      await contract.revertsTransaction()
      fail()
    except ErrorWithArguments as error:
      check error.arguments.one == 1.u256
      check error.arguments.two == true

  test "handles errors when only doing gas estimation":
    proc revertsTransaction(contract: TestCustomErrors)
      {.contract, errors:[ErrorWithArguments], used.}

    let contract = contract.connect(provider.getSigner())
    try:
      discard await contract.estimateGas.revertsTransaction()
      fail()
    except ErrorWithArguments as error:
      check error.arguments.one == 1.u256
      check error.arguments.two == true

  test "handles transaction submission errors":
    proc revertsTransaction(contract: TestCustomErrors)
      {.contract, errors:[ErrorWithArguments].}

     # skip gas estimation
    let overrides = TransactionOverrides(gasLimit: some 1000000.u256)

    let contract = contract.connect(provider.getSigner())
    try:
      await contract.revertsTransaction(overrides = overrides)
      fail()
    except ErrorWithArguments as error:
      check error.arguments.one == 1.u256
      check error.arguments.two == true

  test "handles transaction confirmation errors":
    proc revertsTransaction(contract: TestCustomErrors): Confirmable
      {.contract, errors:[ErrorWithArguments].}

     # skip gas estimation
    let overrides = TransactionOverrides(gasLimit: some 1000000.u256)

    # ensure that transaction is not immediately checked by hardhat
    discard await provider.send("evm_setAutomine", @[%false])

    let contract = contract.connect(provider.getSigner())
    try:
      let future = contract.revertsTransaction(overrides = overrides).confirm(1)
      await sleepAsync(100.millis) # wait for transaction to be submitted
      discard await provider.send("evm_mine", @[]) # mine the transaction
      discard await future # wait for confirmation
      fail()
    except ErrorWithArguments as error:
      check error.arguments.one == 1.u256
      check error.arguments.two == true

    # re-enable auto mining
    discard await provider.send("evm_setAutomine", @[%true])
