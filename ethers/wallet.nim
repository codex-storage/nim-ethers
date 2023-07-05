import eth/keys
import eth/rlp
import eth/common
import eth/common/transaction as ct
import ./provider
import ./transaction as tx
import ./signer

export keys

var rng {.threadvar.}: ref HmacDrbgContext

proc getRng: ref HmacDrbgContext =
  if rng.isNil:
    rng = newRng()
  rng

type SignableTransaction = common.Transaction

type WalletError* = object of EthersError
type Wallet* = ref object of Signer
  privateKey*: PrivateKey
  publicKey*: PublicKey
  address*: Address
  provider*: ?Provider

proc new*(_: type Wallet, privateKey: PrivateKey): Wallet =
  let publicKey = privateKey.toPublicKey()
  let address = Address.init(publicKey.toCanonicalAddress())
  Wallet(privateKey: privateKey, publicKey: publicKey, address: address)
proc new*(_: type Wallet, privateKey: PrivateKey, provider: Provider): Wallet =
  let wallet = Wallet.new(privateKey)
  wallet.provider = some provider
  wallet
proc new*(_: type Wallet, privateKey: string): Wallet =
  Wallet.new(PrivateKey.fromHex(privateKey).value)
proc new*(_: type Wallet, privateKey: string, provider: Provider): Wallet =
  Wallet.new(PrivateKey.fromHex(privateKey).value, provider)
proc connect*(wallet: Wallet, provider: Provider) =
  wallet.provider = some provider
proc createRandom*(_: type Wallet): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.random(getRng()[])
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address.init(result.publicKey.toCanonicalAddress())
proc createRandom*(_: type Wallet, provider: Provider): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.random(getRng()[])
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address.init(result.publicKey.toCanonicalAddress())
  result.provider = some provider

method provider*(wallet: Wallet): Provider =
  without provider =? wallet.provider:
    raise newException(WalletError, "Wallet has no provider")
  provider

method getAddress(wallet: Wallet): Future[Address] {.async.} =
  return wallet.address

proc signTransaction(tr: var SignableTransaction, pk: PrivateKey) =
  let h = tr.txHashNoSignature
  let s = sign(pk, SkMessage(h.data))

  let r = toRaw(s)
  let v = r[64]

  tr.R = fromBytesBE(UInt256, r.toOpenArray(0, 31))
  tr.S = fromBytesBE(UInt256, r.toOpenArray(32, 63))

  case tr.txType:
  of TxLegacy:
    #tr.V = int64(v) + int64(tr.chainId)*2 + 35  #TODO does not work, not sure why. Sending the tx results in error of too little funds. Maybe something wrong with signature and a wrong sender gets encoded?
    tr.V = int64(v) + 27
  of TxEip1559:
    tr.V = int64(v)
  else:
    raise newException(WalletError, "Transaction type not supported")

proc signTransaction*(wallet: Wallet, tx: tx.Transaction): Future[seq[byte]] {.async.} =
  if sender =? tx.sender and sender != wallet.address:
    raise newException(WalletError, "from address mismatch")

  without nonce =? tx.nonce and chainId =? tx.chainId and gasLimit =? tx.gasLimit:
    raise newException(WalletError, "Transaction is properly populated")

  var s: SignableTransaction

  if maxFee =? tx.maxFee and maxPriorityFee =? tx.maxPriorityFee:
    s.txType = TxEip1559
    s.maxFee = GasInt(maxFee.truncate(uint64))
    s.maxPriorityFee = GasInt(maxPriorityFee.truncate(uint64))
  elif gasPrice =? tx.gasPrice:
    s.txType = TxLegacy
    s.gasPrice = GasInt(gasPrice.truncate(uint64))
  else:
    raise newException(WalletError, "Transaction is properly populated")

  s.chainId = ChainId(chainId.truncate(uint64))
  s.gasLimit = GasInt(gasLimit.truncate(uint64))
  s.nonce = nonce.truncate(uint64)
  s.to = some EthAddress(tx.to)
  s.payload = tx.data
  signTransaction(s, wallet.privateKey)

  return rlp.encode(s)

method sendTransaction*(wallet: Wallet, tx: tx.Transaction): Future[TransactionResponse] {.async.} =
  let rawTX = await signTransaction(wallet, tx)
  return await provider(wallet).sendTransaction(rawTX)

#TODO add functionality to sign messages

#TODO add functionality to create wallets from Mnemoniks or Keystores
