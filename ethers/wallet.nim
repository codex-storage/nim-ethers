import eth/keys
import eth/rlp
import eth/common
import eth/common/transaction as ct
import ./provider
import ./transaction as tx
import ./signer
import ./wallet/error

export keys
export WalletError

var rng {.threadvar.}: ref HmacDrbgContext

proc getRng: ref HmacDrbgContext =
  if rng.isNil:
    rng = newRng()
  rng

type SignableTransaction = common.Transaction

type Wallet* = ref object of Signer
  privateKey*: PrivateKey
  publicKey*: PublicKey
  address*: Address
  provider*: ?Provider

proc new*(_: type Wallet, pk: string, provider: Provider): Wallet =
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
    raiseWalletError "Wallet has no provider"
  provider

method getAddress(wallet: Wallet): Future[Address] {.async.} =
  return wallet.address

proc signTransaction(tr: var SignableTransaction, pk: PrivateKey) =
  # Temporary V value, used to signal to the hashing function the
  # chain id that we'd like to use for an EIP-155 signature
  tr.V = int64(uint64(tr.chainId)) * 2 + 35

  let h = tr.txHashNoSignature
  let s = sign(pk, SkMessage(h.data))

  let r = toRaw(s)
  let v = r[64]

  tr.R = fromBytesBE(UInt256, r.toOpenArray(0, 31))
  tr.S = fromBytesBE(UInt256, r.toOpenArray(32, 63))

  case tr.txType:
  of TxLegacy:
    tr.V = int64(v) + int64(uint64(tr.chainId))*2 + 35
  of TxEip1559:
    tr.V = int64(v)
  else:
    raiseWalletError "Transaction type not supported"

proc signTransaction*(wallet: Wallet, tx: tx.Transaction): Future[seq[byte]] {.async.} =
  if sender =? tx.sender and sender != wallet.address:
    raiseWalletError "from address mismatch"

  without nonce =? tx.nonce and chainId =? tx.chainId and gasLimit =? tx.gasLimit:
    raiseWalletError "Transaction is not properly populated"

  var s: SignableTransaction

  if maxFee =? tx.maxFee and maxPriorityFee =? tx.maxPriorityFee:
    s.txType = TxEip1559
    s.maxFee = GasInt(maxFee.truncate(uint64))
    s.maxPriorityFee = GasInt(maxPriorityFee.truncate(uint64))
  elif gasPrice =? tx.gasPrice:
    s.txType = TxLegacy
    s.gasPrice = GasInt(gasPrice.truncate(uint64))
  else:
    raiseWalletError "Transaction is not properly populated"

  s.chainId = ChainId(chainId.truncate(uint64))
  s.gasLimit = GasInt(gasLimit.truncate(uint64))
  s.value = tx.value
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
