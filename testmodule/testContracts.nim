import std/json
import std/options
import pkg/asynctest
import pkg/questionable
import pkg/stew/byteutils
import pkg/stint
import pkg/ethers
import pkg/ethers/erc20
import pkg/ethers/testing
import ./hardhat
import ./helpers
import ./miner
import ./mocks

type
  TestToken = ref object of Erc20Token

method mint(token: TestToken, holder: Address, amount: UInt256): ?TransactionResponse {.base, contract.}
method myBalance(token: TestToken): UInt256 {.base, contract, view.}

for url in ["ws://localhost:8545", "http://localhost:8545"]:

  suite "Contracts (" & url & ")":

    var token: TestToken
    var provider: JsonRpcProvider
    var snapshot: JsonNode
    var accounts: seq[Address]

    setup:
      provider = JsonRpcProvider.new(url, pollingInterval = 100.millis)
      snapshot = await provider.send("evm_snapshot")
      accounts = await provider.listAccounts()
      let deployment = readDeployment()
      token = TestToken.new(!deployment.address(TestToken), provider)

    teardown:
      discard await provider.send("evm_revert", @[snapshot])
      await provider.close()

    test "can call constant functions":
      check (await token.name()) == "TestToken"
      check (await token.totalSupply()) == 0.u256
      check (await token.balanceOf(accounts[0])) == 0.u256
      check (await token.allowance(accounts[0], accounts[1])) == 0.u256

    test "can call non-constant functions":
      token = TestToken.new(token.address, provider.getSigner())
      discard await token.mint(accounts[1], 100.u256)
      check (await token.totalSupply()) == 100.u256
      check (await token.balanceOf(accounts[1])) == 100.u256

    test "can call constant functions with a signer and the account is used for the call":
      let signer0 = provider.getSigner(accounts[0])
      let signer1 = provider.getSigner(accounts[1])
      discard await token.connect(signer0).mint(accounts[1], 100.u256)
      check (await token.connect(signer0).myBalance()) == 0.u256
      check (await token.connect(signer1).myBalance()) == 100.u256

    test "can call non-constant functions without a signer":
      discard await token.mint(accounts[1], 100.u256)
      check (await token.balanceOf(accounts[1])) == 0.u256

    test "can call constant functions without a return type":
      token = TestToken.new(token.address, provider.getSigner())
      proc mint(token: TestToken, holder: Address, amount: UInt256) {.contract, view.}
      await mint(token, accounts[1], 100.u256)
      check (await balanceOf(token, accounts[1])) == 0.u256

    test "can call non-constant functions without a return type":
      token = TestToken.new(token.address, provider.getSigner())
      proc mint(token: TestToken, holder: Address, amount: UInt256) {.contract.}
      await token.mint(accounts[1], 100.u256)
      check (await balanceOf(token, accounts[1])) == 100.u256

    test "can call non-constant functions with a ?TransactionResponse return type":
      token = TestToken.new(token.address, provider.getSigner())
      proc mint(token: TestToken,
                holder: Address,
                amount: UInt256): ?TransactionResponse {.contract.}
      let txResp = await token.mint(accounts[1], 100.u256)
      check txResp is (?TransactionResponse)
      check txResp.isSome

    test "can call non-constant functions with a Confirmable return type":

      token = TestToken.new(token.address, provider.getSigner())
      proc mint(token: TestToken,
                holder: Address,
                amount: UInt256): Confirmable {.contract.}
      let txResp = await token.mint(accounts[1], 100.u256)
      check txResp is Confirmable
      check txResp.isSome

    test "fails to compile when function has an implementation":
      let works = compiles:
        proc foo(token: TestToken, bar: Address) {.contract.} = discard
      check not works

    test "fails to compile when function has no parameters":
      let works = compiles:
        proc foo() {.contract.}
      check not works

    test "fails to compile when non-constant function has a return type":
      let works = compiles:
        proc foo(token: TestToken, bar: Address): UInt256 {.contract.}
      check not works

    test "can connect to different providers and signers":
      let signer0 = provider.getSigner(accounts[0])
      let signer1 = provider.getSigner(accounts[1])
      discard await token.connect(signer0).mint(accounts[0], 100.u256)
      discard await token.connect(signer0).transfer(accounts[1], 50.u256)
      discard await token.connect(signer1).transfer(accounts[2], 25.u256)
      check (await token.connect(provider).balanceOf(accounts[0])) == 50.u256
      check (await token.connect(provider).balanceOf(accounts[1])) == 25.u256
      check (await token.connect(provider).balanceOf(accounts[2])) == 25.u256

    test "takes custom values for nonce, gasprice and gaslimit":
      let overrides = TransactionOverrides(
        nonce: some 100.u256,
        gasPrice: some 200.u256,
        gasLimit: some 300.u256
      )
      let signer = MockSigner.new(provider)
      discard await token.connect(signer).mint(accounts[0], 42.u256, overrides)
      check signer.transactions.len == 1
      check signer.transactions[0].nonce == overrides.nonce
      check signer.transactions[0].gasPrice == overrides.gasPrice
      check signer.transactions[0].gasLimit == overrides.gasLimit

    test "can call functions for different block heights":
      let block1 = await provider.getBlockNumber()
      let signer = provider.getSigner(accounts[0])
      discard await token.connect(signer).mint(accounts[0], 100.u256)
      let block2 = await provider.getBlockNumber()

      let beforeMint = CallOverrides(blockTag: some BlockTag.init(block1))
      let afterMint = CallOverrides(blockTag: some BlockTag.init(block2))

      check (await token.balanceOf(accounts[0], beforeMint)) == 0
      check (await token.balanceOf(accounts[0], afterMint)) == 100

    test "receives events when subscribed":
      var transfers: seq[Transfer]

      proc handleTransfer(transfer: Transfer) =
        transfers.add(transfer)

      let signer0 = provider.getSigner(accounts[0])
      let signer1 = provider.getSigner(accounts[1])

      let subscription = await token.subscribe(Transfer, handleTransfer)
      discard await token.connect(signer0).mint(accounts[0], 100.u256)
      discard await token.connect(signer0).transfer(accounts[1], 50.u256)
      discard await token.connect(signer1).transfer(accounts[2], 25.u256)

      check eventually transfers == @[
        Transfer(receiver: accounts[0], value: 100.u256),
        Transfer(sender: accounts[0], receiver: accounts[1], value: 50.u256),
        Transfer(sender: accounts[1], receiver: accounts[2], value: 25.u256)
      ]

      await subscription.unsubscribe()

    test "stops receiving events when unsubscribed":
      var transfers: seq[Transfer]

      proc handleTransfer(transfer: Transfer) =
        transfers.add(transfer)

      let signer0 = provider.getSigner(accounts[0])

      let subscription = await token.subscribe(Transfer, handleTransfer)
      discard await token.connect(signer0).mint(accounts[0], 100.u256)

      check eventually transfers.len == 1
      await subscription.unsubscribe()

      discard await token.connect(signer0).transfer(accounts[1], 50.u256)
      await sleepAsync(100.millis)

      check transfers.len == 1

    test "can wait for contract interaction tx to be mined":
      let signer0 = provider.getSigner(accounts[0])
      let confirming = token.connect(signer0)
                            .mint(accounts[1], 100.u256)
                            .confirm(3)
      await sleepAsync(100.millis) # wait for tx to be mined
      await provider.mineBlocks(2) # two additional blocks
      let receipt = await confirming
      check receipt.blockNumber.isSome

    test "can query last block event log":

      let signer0 = provider.getSigner(accounts[0])

      discard await token.connect(signer0).mint(accounts[0], 100.u256)
      discard await token.connect(signer0).transfer(accounts[1], 50.u256)

      let logs = await token.queryFilter(Transfer)

      check eventually logs == @[
        Transfer(sender: accounts[0], receiver: accounts[1], value: 50.u256)
      ]

    test "can query past event logs by specifying from and to blocks":

      let signer0 = provider.getSigner(accounts[0])
      let signer1 = provider.getSigner(accounts[1])

      discard await token.connect(signer0).mint(accounts[0], 100.u256)
      discard await token.connect(signer0).transfer(accounts[1], 50.u256)
      discard await token.connect(signer1).transfer(accounts[2], 25.u256)

      let currentBlock = await provider.getBlockNumber()
      let logs = await token.queryFilter(Transfer,
                                         BlockTag.init(currentBlock - 1),
                                         BlockTag.latest)

      check logs == @[
        Transfer(sender: accounts[0], receiver: accounts[1], value: 50.u256),
        Transfer(sender: accounts[1], receiver: accounts[2], value: 25.u256)
      ]

    test "can query past event logs by specifying a block hash":

      let signer0 = provider.getSigner(accounts[0])

      let receipt = await token.connect(signer0)
                               .mint(accounts[0], 100.u256)
                               .confirm(1)
      discard await token.connect(signer0).transfer(accounts[1], 50.u256)

      let logs = await token.queryFilter(Transfer, !receipt.blockHash)

      check logs == @[
        Transfer(receiver: accounts[0], value: 100.u256)
      ]

    test "concurrent transactions with first failing increment nonce correctly":
      let signer = provider.getSigner()
      let token = TestToken.new(token.address, signer)
      let helpersContract = TestHelpers.new(signer)

      # emulate concurrent populateTransaction calls, where the first one fails
      let futs = await allFinished(
        helpersContract.doRevert("some reason"),
        token.mint(accounts[0], 100.u256)
      )
      check futs[0].error of EstimateGasError
      let receipt = await futs[1].confirm(1)

      check receipt.status == TransactionStatus.Success

    test "non-concurrent transactions with first failing increment nonce correctly":
      let signer = provider.getSigner()
      let token = TestToken.new(token.address, signer)
      let helpersContract = TestHelpers.new(signer)

      expect EstimateGasError:
        discard await helpersContract.doRevert("some reason")

      let receipt = await token
        .mint(accounts[0], 100.u256)
        .confirm(1)

      check receipt.status == TransactionStatus.Success
