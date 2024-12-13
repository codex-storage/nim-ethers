import eth/keys
import ../basics
import ../provider
import ../transaction
import ../signer
import ./wallet/error
import ./wallet/signing

export keys
export WalletError
export signing

{.push raises: [].}

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
  let address = Address(publicKey.toCanonicalAddress())
  Wallet(privateKey: privateKey, publicKey: publicKey, address: address)

proc new*(_: type Wallet, privateKey: PrivateKey, provider: Provider): Wallet =
  let wallet = Wallet.new(privateKey)
  wallet.provider = some provider
  wallet

proc new*(_: type Wallet, privateKey: string): ?!Wallet =
  let keyResult = PrivateKey.fromHex(privateKey)
  if keyResult.isErr:
    return failure newException(WalletError, "invalid key: " & $keyResult.error)
  success Wallet.new(keyResult.get())

proc new*(_: type Wallet, privateKey: string, provider: Provider): ?!Wallet =
  let wallet = ? Wallet.new(privateKey)
  wallet.provider = some provider
  success wallet

proc connect*(wallet: Wallet, provider: Provider) =
  wallet.provider = some provider

proc createRandom*(_: type Wallet): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.random(getRng()[])
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address(result.publicKey.toCanonicalAddress())

proc createRandom*(_: type Wallet, provider: Provider): Wallet =
  result = Wallet()
  result.privateKey = PrivateKey.random(getRng()[])
  result.publicKey = result.privateKey.toPublicKey()
  result.address = Address(result.publicKey.toCanonicalAddress())
  result.provider = some provider

method provider*(wallet: Wallet): Provider {.gcsafe, raises: [SignerError].} =
  without provider =? wallet.provider:
    raiseWalletError "Wallet has no provider"
  provider

method getAddress*(
  wallet: Wallet): Future[Address]
  {.async: (raises:[ProviderError, SignerError]).} =

  return wallet.address

proc signTransaction*(wallet: Wallet,
                      transaction: Transaction): Future[seq[byte]] {.async: (raises:[WalletError]).} =
  if sender =? transaction.sender and sender != wallet.address:
    raiseWalletError "from address mismatch"

  return wallet.privateKey.sign(transaction)

method sendTransaction*(
  wallet: Wallet,
  transaction: Transaction): Future[TransactionResponse]
  {.async: (raises:[SignerError, ProviderError]).} =

  let signed = await signTransaction(wallet, transaction)
  return await provider(wallet).sendTransaction(signed)
