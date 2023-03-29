import std/json
import pkg/asynctest
import pkg/questionable
import pkg/stint
import pkg/ethers
import pkg/ethers/erc20
import ./hardhat
import ./miner
import ./mocks

type
  TestToken = ref object of Erc20Token

method mint(token: TestToken, holder: Address, amount: UInt256): ?TransactionResponse {.base, contract.}
method burn(token: TestToken, holder: Address, amount: UInt256): ?TransactionResponse {.base, contract.}

suite "ERC20":

  var token, token1: Erc20Token
  var testToken: TestToken
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  var accounts: seq[Address]

  setup:
    provider = JsonRpcProvider.new("ws://localhost:8545")
    snapshot = await provider.send("evm_snapshot")
    accounts = await provider.listAccounts()
    let deployment = readDeployment()
    testToken = TestToken.new(!deployment.address(TestToken), provider.getSigner())
    token = Erc20Token.new(!deployment.address(TestToken), provider.getSigner())

    let signer1 = provider.getSigner(accounts[1])
    token1 = Erc20Token.new(!deployment.address(TestToken), signer1)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])

  test "retrieves basic information":
    check (await token.name()) == "TestToken"
    check (await token.symbol()) == "TST"
    check (await token.decimals()) == 12
    check (await token.totalSupply()) == 0.u256
    check (await token.balanceOf(accounts[0])) == 0.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256

  test "transfer tokens":
    check (await token.balanceOf(accounts[0])) == 0.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256

    discard await testToken.mint(accounts[0], 100.u256)

    check (await token.totalSupply()) == 100.u256
    check (await token.balanceOf(accounts[0])) == 100.u256
    check (await token.balanceOf(accounts[1])) == 0.u256

    await token.transfer(accounts[1], 50.u256)

    check (await token.balanceOf(accounts[0])) == 50.u256
    check (await token.balanceOf(accounts[1])) == 50.u256

  test "approve tokens":
    check (await token.balanceOf(accounts[0])) == 0.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256

    discard await testToken.mint(accounts[0], 100.u256)

    check (await token.totalSupply()) == 100.u256
    check (await token.balanceOf(accounts[0])) == 100.u256
    check (await token.balanceOf(accounts[1])) == 0.u256

    await token.approve(accounts[1], 50.u256)

    check (await token.allowance(accounts[0], accounts[1])) == 50.u256
    check (await token.balanceOf(accounts[0])) == 100.u256
    check (await token.balanceOf(accounts[1])) == 0.u256

  test "transferFrom tokens":
    check (await token.balanceOf(accounts[0])) == 0.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256

    discard await testToken.mint(accounts[0], 100.u256)

    check (await token.totalSupply()) == 100.u256
    check (await token.balanceOf(accounts[0])) == 100.u256
    check (await token.balanceOf(accounts[1])) == 0.u256

    await token.approve(accounts[1], 50.u256)

    check (await token.allowance(accounts[0], accounts[1])) == 50.u256
    check (await token.balanceOf(accounts[0])) == 100.u256
    check (await token.balanceOf(accounts[1])) == 0.u256

    await token1.transferFrom(accounts[0], accounts[1], 50.u256)

    check (await token.balanceOf(accounts[0])) == 50.u256
    check (await token.balanceOf(accounts[1])) == 50.u256
    check (await token.allowance(accounts[0], accounts[1])) == 0.u256
