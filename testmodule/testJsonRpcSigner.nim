import pkg/asynctest
import pkg/ethers

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
