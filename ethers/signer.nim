import ./basics
import ./provider
import pkg/chronicles

export basics
export chronicles

logScope:
  topics = "ethers signer"

type
  Signer* = ref object of RootObj
    lastSeenNonce: ?UInt256
    populateLock: AsyncLock

type
  SignerError* = object of EthersError
  EstimateGasError* = object of SignerError
    transaction*: Transaction

template raiseSignerError(message: string, parent: ref ProviderError = nil) =
  raise newException(SignerError, message, parent)

proc raiseEstimateGasError(
  transaction: Transaction,
  parent: ref ProviderError = nil
) =
  let e = (ref EstimateGasError)(
    msg: "Estimate gas failed",
    transaction: transaction,
    parent: parent)
  raise e

method provider*(signer: Signer): Provider {.base, gcsafe.} =
  doAssert false, "not implemented"

method getAddress*(signer: Signer): Future[Address] {.base, gcsafe.} =
  doAssert false, "not implemented"

method signMessage*(signer: Signer,
                    message: seq[byte]): Future[seq[byte]] {.base, async.} =
  doAssert false, "not implemented"

method sendTransaction*(signer: Signer,
                        transaction: Transaction): Future[TransactionResponse] {.base, async.} =
  doAssert false, "not implemented"

method getGasPrice*(signer: Signer): Future[UInt256] {.base, gcsafe.} =
  signer.provider.getGasPrice()

method getTransactionCount*(signer: Signer,
                            blockTag = BlockTag.latest):
                           Future[UInt256] {.base, async.} =
  let address = await signer.getAddress()
  return await signer.provider.getTransactionCount(address, blockTag)

method estimateGas*(signer: Signer,
                    transaction: Transaction): Future[UInt256] {.base, async.} =
  var transaction = transaction
  transaction.sender = some(await signer.getAddress)
  try:
    return await signer.provider.estimateGas(transaction)
  except ProviderError as e:
    raiseEstimateGasError transaction, e

method getChainId*(signer: Signer): Future[UInt256] {.base, gcsafe.} =
  signer.provider.getChainId()

method getNonce(signer: Signer): Future[UInt256] {.base, gcsafe, async.} =
  var nonce = await signer.getTransactionCount(BlockTag.pending)

  if lastSeen =? signer.lastSeenNonce and lastSeen >= nonce:
    nonce = (lastSeen + 1.u256)
  signer.lastSeenNonce = some nonce

  return nonce

method updateNonce*(
  signer: Signer,
  nonce: UInt256
) {.base, gcsafe.} =

  without lastSeen =? signer.lastSeenNonce:
    signer.lastSeenNonce = some nonce
    return

  if nonce > lastSeen:
    signer.lastSeenNonce = some nonce

method decreaseNonce*(signer: Signer) {.base, gcsafe.} =
  if lastSeen =? signer.lastSeenNonce and lastSeen > 0:
    signer.lastSeenNonce = some lastSeen - 1

proc ensureNonceSequence(
  signer: Signer,
  tx: Transaction
): Future[Transaction] {.async.} =
  ## Ensures that once the nonce is incremented, if estimate gas fails, the
  ## nonce is decremented. Disallows concurrent calls by use of AsyncLock.
  ## Immediately returns if tx already has a nonce or gasLimit.

  if not (tx.nonce.isNone and tx.gasLimit.isNone):
    return tx

  var populated = tx
  if signer.populateLock.isNil:
    signer.populateLock = newAsyncLock()

  await signer.populateLock.acquire()

  try:
    populated.nonce = some(await signer.getNonce())
    populated.gasLimit = some(await signer.estimateGas(populated))
  except ProviderError, EstimateGasError:
    let e = getCurrentException()
    signer.decreaseNonce()
    raise e
  finally:
    signer.populateLock.release()

  return populated

method populateTransaction*(signer: Signer,
                            transaction: Transaction):
                           Future[Transaction] {.base, async.} =

  if sender =? transaction.sender and sender != await signer.getAddress():
    raiseSignerError("from address mismatch")
  if chainId =? transaction.chainId and chainId != await signer.getChainId():
    raiseSignerError("chain id mismatch")

  var populated = await signer.ensureNonceSequence(transaction)

  if populated.sender.isNone:
    populated.sender = some(await signer.getAddress())
  if populated.chainId.isNone:
    populated.chainId = some(await signer.getChainId())
  if populated.gasPrice.isNone and (populated.maxFee.isNone or populated.maxPriorityFee.isNone):
    populated.gasPrice = some(await signer.getGasPrice())
  if populated.nonce.isNone:
    populated.nonce = some(await signer.getNonce())
  if populated.gasLimit.isNone:
          populated.gasLimit = some(await signer.estimateGas(populated))

  return populated

method cancelTransaction*(
  signer: Signer,
  tx: Transaction
): Future[TransactionResponse] {.async, base.} =
  # cancels a transaction by sending with a 0-valued transaction to ourselves
  # with the failed tx's nonce

  without sender =? tx.sender:
    raiseSignerError "transaction must have sender"
  without nonce =? tx.nonce:
    raiseSignerError "transaction must have nonce"

  var cancelTx = Transaction(to: sender, value: 0.u256, nonce: some nonce)
  cancelTx = await signer.populateTransaction(cancelTx)
  return await signer.sendTransaction(cancelTx)
