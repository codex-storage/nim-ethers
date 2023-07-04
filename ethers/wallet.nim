import eth/keys
import ./provider
import ./transaction
import ./signer
import ./wallet/error
import ./wallet/signing

export keys
export WalletError

var rng {.threadvar.}: ref HmacDrbgContext

proc getRng: ref HmacDrbgContext =
  if rng.isNil:
    rng = newRng()
  rng

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

proc signTransaction*(wallet: Wallet,
                      transaction: Transaction): Future[seq[byte]] {.async.} =
  if sender =? transaction.sender and sender != wallet.address:
    raiseWalletError "from address mismatch"

  return wallet.privateKey.sign(transaction)

method sendTransaction*(wallet: Wallet, transaction: Transaction): Future[TransactionResponse] {.async.} =
  let signed = await signTransaction(wallet, transaction)
  return await provider(wallet).sendTransaction(signed)
