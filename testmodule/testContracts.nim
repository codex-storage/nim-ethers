import std/json
import pkg/asynctest
import pkg/stint
import pkg/ethers
import ./hardhat

type
  Erc20* = ref object of Contract
  TestToken = ref object of Erc20

method totalSupply*(erc20: Erc20): UInt256 {.base, contract.}
method balanceOf*(erc20: Erc20, account: Address): UInt256 {.base, contract.}
method allowance*(erc20: Erc20, owner, spender: Address): UInt256 {.base, contract.}

suite "Contracts":

  var token: TestToken
  var provider: JsonRpcProvider
  var snapshot: JsonNode

  setup:
    provider = JsonRpcProvider.new()
    snapshot = await provider.send("evm_snapshot")
    let deployment = readDeployment()
    token = TestToken.new(!deployment.address(TestToken), provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])

  test "can call view methods":
    let accounts = await provider.listAccounts()
    check (await token.totalSupply()) == 0.u256
    check (await token.balanceOf(accounts[0])) == 0.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256
