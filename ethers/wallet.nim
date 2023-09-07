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
  wallet.updateNonce(transaction.nonce)
  return await provider(wallet).sendTransaction(signed)
