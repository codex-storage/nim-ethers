import std/json
import pkg/asynctest
import pkg/stint
import pkg/ethers
import ./hardhat

type
  Erc20* = ref object of Contract
  TestToken = ref object of Erc20

method totalSupply*(erc20: Erc20): UInt256 {.base, contract, view.}
method balanceOf*(erc20: Erc20, account: Address): UInt256 {.base, contract, view.}
method allowance*(erc20: Erc20, owner, spender: Address): UInt256 {.base, contract, view.}

method mint(token: TestToken, holder: Address, amount: UInt256) {.base, contract.}

suite "Contracts":

  var token: TestToken
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  var accounts: seq[Address]

  setup:
    provider = JsonRpcProvider.new()
    snapshot = await provider.send("evm_snapshot")
    accounts = await provider.listAccounts()
    let deployment = readDeployment()
    token = TestToken.new(!deployment.address(TestToken), provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])

  test "can call constant functions":
    check (await token.totalSupply()) == 0.u256
    check (await token.balanceOf(accounts[0])) == 0.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256

  test "can call non-constant functions":
    token = TestToken.new(token.address, provider.getSigner())
    await token.mint(accounts[1], 100.u256)
    check (await token.totalSupply()) == 100.u256
    check (await token.balanceOf(accounts[1])) == 100.u256

  test "can call non-constant functions without a signer":
    await token.mint(accounts[1], 100.u256)
    check (await token.balanceOf(accounts[1])) == 0.u256

  test "can call constant functions without a return type":
    token = TestToken.new(token.address, provider.getSigner())
    proc mint(token: TestToken, holder: Address, amount: UInt256) {.contract, view.}
    await mint(token, accounts[1], 100.u256)
    check (await balanceOf(token, accounts[1])) == 0.u256

  test "fails to compile when non-constant function has a return type":
    let works = compiles:
      proc foo(token: TestToken, bar: Address): UInt256 {.contract.}
    check not works
