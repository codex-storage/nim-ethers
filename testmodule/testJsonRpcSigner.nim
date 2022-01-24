import pkg/asynctest
import pkg/ethers
import ./examples

suite "JsonRpcSigner":

  var provider: JsonRpcProvider
  var accounts: seq[Address]

  setup:
    provider = JsonRpcProvider.new()
    accounts = await provider.listAccounts()

  test "is connected to the first account of the provider by default":
    let signer = provider.getSigner()
    check (await signer.getAddress()) == accounts[0]

  test "can connect to a different account":
    let signer = provider.getSigner(accounts[1])
    check (await signer.getAddress()) == accounts[1]

  test "can retrieve gas price":
    let signer = provider.getSigner()
    let gasprice = await signer.getGasPrice()
    check gasprice > 0.u256

  test "can retrieve transaction count":
    let signer = provider.getSigner(accounts[9])
    let count = await signer.getTransactionCount(BlockTag.pending)
    check count == 0.u256

  test "can estimate gas cost of a transaction":
    let signer = provider.getSigner()
    let estimate = await signer.estimateGas(Transaction.example)
    check estimate > 0.u256

  test "can retrieve chain id":
    let signer = provider.getSigner()
    let chainId = await signer.getChainId()
    check chainId == 31337.u256 # hardhat chain id
