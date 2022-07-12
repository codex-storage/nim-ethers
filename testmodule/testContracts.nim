import std/json
import pkg/asynctest
import pkg/questionable
import pkg/stint
import pkg/ethers
import ./hardhat
import ./miner
import ./mocks

type

  Erc20* = ref object of Contract
  TestToken = ref object of Erc20

  Transfer = object of Event
    sender {.indexed.}: Address
    receiver {.indexed.}: Address
    value: UInt256

method name*(erc20: Erc20): string {.base, contract, view.}
method totalSupply*(erc20: Erc20): UInt256 {.base, contract, view.}
method balanceOf*(erc20: Erc20, account: Address): UInt256 {.base, contract, view.}
method allowance*(erc20: Erc20, owner, spender: Address): UInt256 {.base, contract, view.}
method transfer*(erc20: Erc20, recipient: Address, amount: UInt256) {.base, contract.}
method mint(token: TestToken, holder: Address, amount: UInt256): ?TransactionResponse {.base, contract.}

suite "Contracts":

  var token: TestToken
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  var accounts: seq[Address]

  setup:
    provider = JsonRpcProvider.new("ws://localhost:8545")
    snapshot = await provider.send("evm_snapshot")
    accounts = await provider.listAccounts()
    let deployment = readDeployment()
    token = TestToken.new(!deployment.address(TestToken), provider)

  teardown:
    discard await provider.send("evm_revert", @[snapshot])

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
    await token.connect(signer0).transfer(accounts[1], 50.u256)
    await token.connect(signer1).transfer(accounts[2], 25.u256)
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

  test "receives events when subscribed":
    var transfers: seq[Transfer]

    proc handleTransfer(transfer: Transfer) =
      transfers.add(transfer)

    let signer0 = provider.getSigner(accounts[0])
    let signer1 = provider.getSigner(accounts[1])

    let subscription = await token.subscribe(Transfer, handleTransfer)
    discard await token.connect(signer0).mint(accounts[0], 100.u256)
    await token.connect(signer0).transfer(accounts[1], 50.u256)
    await token.connect(signer1).transfer(accounts[2], 25.u256)
    await subscription.unsubscribe()

    check transfers == @[
      Transfer(receiver: accounts[0], value: 100.u256),
      Transfer(sender: accounts[0], receiver: accounts[1], value: 50.u256),
      Transfer(sender: accounts[1], receiver: accounts[2], value: 25.u256)
    ]

  test "stops receiving events when unsubscribed":
    var transfers: seq[Transfer]

    proc handleTransfer(transfer: Transfer) =
      transfers.add(transfer)

    let signer0 = provider.getSigner(accounts[0])

    let subscription = await token.subscribe(Transfer, handleTransfer)
    discard await token.connect(signer0).mint(accounts[0], 100.u256)
    await subscription.unsubscribe()

    await token.connect(signer0).transfer(accounts[1], 50.u256)

    check transfers == @[Transfer(receiver: accounts[0], value: 100.u256)]

  test "can wait for contract interaction tx to be mined":
    # must not be awaited so we can get newHeads inside of .wait
    let futMined = provider.mineBlocks(10)

    let signer0 = provider.getSigner(accounts[0])
    let receipt = await token.connect(signer0)
                    .mint(accounts[1], 100.u256)
                    .confirm(3) # wait for 3 confirmations
    let endBlock = await provider.getBlockNumber()

    check receipt.blockNumber.isSome # was eventually mined

    # >= 3 because more blocks may have been mined by the time the
    # check in `.wait` was done.
    # +1 for the block the tx was mined in
    check (endBlock - !receipt.blockNumber) + 1 >= 3

    await futMined
