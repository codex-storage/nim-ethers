import eth/keys
import eth/rlp
import eth/common
import eth/common/transaction as ct
import stew/byteutils
import ./providers/jsonrpc
import ./transaction
import ./signer

export keys

let rng = newRng()

type SignableTransaction = common.Transaction

type WalletError* = object of EthersError
type Wallet* = ref object of Signer
  privateKey*: PrivateKey
  publicKey*: PublicKey
  address*: Address
  provider*: ?JsonRpcProvider

proc new*(_: type Wallet, pk: string, provider: JsonRpcProvider): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.fromHex(pk).value
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address.init(result.publicKey.toCanonicalAddress())
  result.provider = some provider
proc new*(_: type Wallet, pk: string): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.fromHex(pk).value
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address.init(result.publicKey.toCanonicalAddress())
proc connect*(wallet: Wallet, provider: JsonRpcProvider) =
  wallet.provider = some provider
proc createRandom*(_: type Wallet): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.random(rng[])
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address.init(result.publicKey.toCanonicalAddress())
proc createRandom*(_: type Wallet, provider: JsonRpcProvider): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.random(rng[])
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address.init(result.publicKey.toCanonicalAddress())
  result.provider = some provider

method populateTransaction*(wallet: Wallet, tx: transaction.Transaction): Future[transaction.Transaction] {.async.} =
  var populated = tx
  if tx.nonce.isNone:
    populated.nonce = some(await wallet.getTransactionCount(BlockTag.pending))
  if tx.chainId.isNone:
    populated.chainId = some(await wallet.getChainId())
  if tx.gasLimit.isNone:
    populated.gasLimit = some(await wallet.estimateGas(populated))
  if tx.gasPrice.isNone and (tx.maxFee.isNone and tx.maxPriorityFee.isNone):
    populated.gasPrice = some(await wallet.getGasPrice())
  return populated

func isPopulated(tx: transaction.Transaction) =
  if tx.nonce.isNone or
     tx.chainId.isNone or
     tx.gasLimit.isNone or
     (tx.gasPrice.isNone and (tx.maxFee.isNone or tx.maxPriorityFee.isNone)):
    raise newException(WalletError, "Transaction is not properly populated")

proc signTransaction(tr: var SignableTransaction, pk: PrivateKey) =
  let h = tr.txHashNoSignature
  let s = sign(pk, SkMessage(h.data))

  let r = toRaw(s)
  let v = r[64]

  tr.R = fromBytesBe(UInt256, r.toOpenArray(0, 31))
  tr.S = fromBytesBE(UInt256, r.toOpenArray(32, 63))

  case tr.txType:
  of TxLegacy:
    #tr.V = int64(v) + int64(tr.chainId)*2 + 35  #TODO does not work, not sure why. Sending the tx results in error of too little funds. Maybe something wrong with signature and a wrong sender gets encoded?
    tr.V = int64(v) + 27
  of TxEip1559:
    tr.V = int64(v)
  else:
    raise newException(WalletError, "Transaction type not supported")

proc sendTransaction*(wallet: Wallet, tx: transaction.Transaction): Future[TransactionResponse] {.async.} =
  if tx.sender.isSome:
    doAssert tx.sender.get == wallet.address, "from Address mismatch"
  isPopulated(tx)
  var s: SignableTransaction
  if tx.maxFee.isSome and tx.maxPriorityFee.isSome:
    s.txType = TxEip1559
    s.maxFee = GasInt(tx.maxFee.get.truncate(uint64))
    s.maxPriorityFee = GasInt(tx.maxPriorityFee.get.truncate(uint64))
  else:
    s.txType = TxLegacy
    s.gasPrice = GasInt(tx.gasPrice.get.truncate(uint64))
  s.chainId = ChainId(tx.chainId.get.truncate(uint64))
  s.gasLimit = GasInt(tx.gasLimit.get.truncate(uint64))
  s.nonce = tx.nonce.get.truncate(uint64)
  s.to = some EthAddress(tx.to)
  s.payload = tx.data
  signTransaction(s, wallet.privateKey)

  let rawTX = "0x" & rlp.encode(s).toHex 
  return await wallet.provider.get.sendRawTransaction(rawTX)

proc signTransaction*(wallet: Wallet, tx: transaction.Transaction): Future[string] {.async.} =
  if tx.sender.isSome:
    doAssert tx.sender.get == wallet.address, "from Address mismatch"
  isPopulated(tx)
  var s: SignableTransaction
  if tx.maxFee.isSome and tx.maxPriorityFee.isSome:
    s.txType = TxEip1559
    s.maxFee = GasInt(tx.maxFee.get.truncate(uint64))
    s.maxPriorityFee = GasInt(tx.maxPriorityFee.get.truncate(uint64))
  else:
    s.txType = TxLegacy
    s.gasPrice = GasInt(tx.gasPrice.get.truncate(uint64))
  s.chainId = ChainId(tx.chainId.get.truncate(uint64))
  s.gasLimit = GasInt(tx.gasLimit.get.truncate(uint64))
  s.nonce = tx.nonce.get.truncate(uint64)
  s.to = some EthAddress(tx.to)
  s.payload = tx.data
  signTransaction(s, wallet.privateKey)
 
  return "0x" & rlp.encode(s).toHex