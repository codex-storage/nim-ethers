import std/os
import pkg/serde
import pkg/asynctest/chronos/unittest
import pkg/questionable
import pkg/stint
import pkg/ethers
import pkg/ethers/erc20
import ./hardhat

type
  TestToken = ref object of Erc20Token

method mint(token: TestToken, holder: Address, amount: UInt256): Confirmable {.base, contract.}

let providerUrl = getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")
for url in ["ws://" & providerUrl, "http://"  & providerUrl]:

  suite "ERC20 (" & url & ")":

    var token: Erc20Token
    var testToken: TestToken
    var provider: JsonRpcProvider
    var snapshot: JsonNode
    var accounts: seq[Address]

    setup:
      provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
      snapshot = await provider.send("evm_snapshot")
      accounts = await provider.listAccounts()
      let deployment = readDeployment()
      testToken = TestToken.new(!deployment.address(TestToken), provider.getSigner())
      token = Erc20Token.new(!deployment.address(TestToken), provider.getSigner())

    teardown:
      discard await provider.send("evm_revert", @[snapshot])
      await provider.close()

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

      discard await token.transfer(accounts[1], 50.u256)

      check (await token.balanceOf(accounts[0])) == 50.u256
      check (await token.balanceOf(accounts[1])) == 50.u256

    test "approve tokens":
      discard await testToken.mint(accounts[0], 100.u256)

      check (await token.allowance(accounts[0], accounts[1])) == 0.u256
      check (await token.balanceOf(accounts[0])) == 100.u256
      check (await token.balanceOf(accounts[1])) == 0.u256

      discard await token.approve(accounts[1], 50.u256)

      check (await token.allowance(accounts[0], accounts[1])) == 50.u256
      check (await token.balanceOf(accounts[0])) == 100.u256
      check (await token.balanceOf(accounts[1])) == 0.u256

    test "increase/decrease allowance":
      discard await testToken.mint(accounts[0], 100.u256)

      check (await token.allowance(accounts[0], accounts[1])) == 0.u256
      check (await token.balanceOf(accounts[0])) == 100.u256
      check (await token.balanceOf(accounts[1])) == 0.u256

      discard await token.increaseAllowance(accounts[1], 50.u256)

      check (await token.allowance(accounts[0], accounts[1])) == 50.u256
      check (await token.balanceOf(accounts[0])) == 100.u256
      check (await token.balanceOf(accounts[1])) == 0.u256

      discard await token.increaseAllowance(accounts[1], 50.u256)

      check (await token.allowance(accounts[0], accounts[1])) == 100.u256
      check (await token.balanceOf(accounts[0])) == 100.u256
      check (await token.balanceOf(accounts[1])) == 0.u256

      discard await token.decreaseAllowance(accounts[1], 50.u256)

      check (await token.allowance(accounts[0], accounts[1])) == 50.u256
      check (await token.balanceOf(accounts[0])) == 100.u256
      check (await token.balanceOf(accounts[1])) == 0.u256


    test "transferFrom tokens":
      let senderAccount = accounts[0]
      let receiverAccount = accounts[1]
      let receiverAccountSigner = provider.getSigner(receiverAccount)

      check (await token.balanceOf(senderAccount)) == 0.u256
      check (await token.allowance(senderAccount, receiverAccount)) == 0.u256

      discard await testToken.mint(senderAccount, 100.u256)

      check (await token.totalSupply()) == 100.u256
      check (await token.balanceOf(senderAccount)) == 100.u256
      check (await token.balanceOf(receiverAccount)) == 0.u256

      discard await token.approve(receiverAccount, 50.u256)

      check (await token.allowance(senderAccount, receiverAccount)) == 50.u256
      check (await token.balanceOf(senderAccount)) == 100.u256
      check (await token.balanceOf(receiverAccount)) == 0.u256

      discard await token.connect(receiverAccountSigner).transferFrom(senderAccount, receiverAccount, 50.u256)

      check (await token.balanceOf(senderAccount)) == 50.u256
      check (await token.balanceOf(receiverAccount)) == 50.u256
      check (await token.allowance(senderAccount, receiverAccount)) == 0.u256

