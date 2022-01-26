import pkg/asynctest
import pkg/ethers
import pkg/stew/byteutils
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

  test "can sign messages":
    let signer = provider.getSigner()
    let message = "hello".toBytes
    check (await signer.signMessage(message)).len == 65

  test "can populate missing fields in a transaction":
    let signer = provider.getSigner()
    let transaction = Transaction.example
    let populated = await signer.populateTransaction(transaction)
    check !populated.sender == await signer.getAddress()
    check !populated.gasPrice == await signer.getGasPrice()
    check !populated.nonce == await signer.getTransactionCount(BlockTag.pending)
    check !populated.gasLimit == await signer.estimateGas(transaction)
    check !populated.chainId == await signer.getChainId()

  test "populate does not overwrite existing fields":
    let signer = provider.getSigner()
    var transaction = Transaction.example
    transaction.sender = some await signer.getAddress()
    transaction.nonce = some UInt256.example
    transaction.chainId = some await signer.getChainId()
    transaction.gasPrice = some UInt256.example
    transaction.gasLimit = some UInt256.example
    let populated = await signer.populateTransaction(transaction)
    check populated == transaction

  test "populate fails when sender does not match signer address":
    let signer = provider.getSigner()
    var transaction = Transaction.example
    transaction.sender = accounts[1].some
    expect SignerError:
      discard await signer.populateTransaction(transaction)

  test "populate fails when chain id does not match":
    let signer = provider.getSigner()
    var transaction = Transaction.example
    transaction.chainId = 0xdeadbeef.u256.some
    expect SignerError:
      discard await signer.populateTransaction(transaction)
