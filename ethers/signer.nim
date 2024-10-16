import ./basics
import ./provider

export basics

type
  Signer* = ref object of RootObj
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
                    transaction: Transaction,
                    blockTag = BlockTag.latest): Future[UInt256] {.base, async.} =
  var transaction = transaction
  transaction.sender = some(await signer.getAddress)
  try:
    return await signer.provider.estimateGas(transaction, blockTag)
  except ProviderError as e:
    raiseEstimateGasError transaction, e

method getChainId*(signer: Signer): Future[UInt256] {.base, gcsafe.} =
  signer.provider.getChainId()

method getNonce(signer: Signer): Future[UInt256] {.base, gcsafe, async.} =
  return await signer.getTransactionCount(BlockTag.pending)

template withLock*(signer: Signer, body: untyped) =
  if signer.populateLock.isNil:
    signer.populateLock = newAsyncLock()

  await signer.populateLock.acquire()
  try:
    body
  finally:
    signer.populateLock.release()

method populateTransaction*(signer: Signer,
                            transaction: Transaction):
                           Future[Transaction] {.base, async.} =
  ## Populates a transaction with sender, chainId, gasPrice, nonce, and gasLimit.
  ## NOTE: to avoid async concurrency issues, this routine should be called with
  ## a lock if it is followed by sendTransaction. For reference, see the `send`
  ## function in contract.nim.

  if sender =? transaction.sender and sender != await signer.getAddress():
    raiseSignerError("from address mismatch")
  if chainId =? transaction.chainId and chainId != await signer.getChainId():
    raiseSignerError("chain id mismatch")

  var populated = transaction

  if transaction.sender.isNone:
    populated.sender = some(await signer.getAddress())
  if transaction.chainId.isNone:
    populated.chainId = some(await signer.getChainId())
  if transaction.gasPrice.isNone and (transaction.maxFee.isNone or transaction.maxPriorityFee.isNone):
    populated.gasPrice = some(await signer.getGasPrice())

  if transaction.nonce.isNone and transaction.gasLimit.isNone:
    # when both nonce and gasLimit are not populated, we must ensure getNonce is
    # followed by an estimateGas so we can determine if there was an error. If
    # there is an error, the nonce must be decreased to prevent nonce gaps and
    # stuck transactions
    let nonce = await signer.getNonce()
    populated.nonce = some nonce
    try:
      populated.gasLimit = some(await signer.estimateGas(populated, BlockTag.pending))
    except ProviderError, EstimateGasError:
      let e = getCurrentException()
      raise e

  else:
    if transaction.nonce.isNone:
      let nonce = await signer.getNonce()
      populated.nonce = some nonce
    if transaction.gasLimit.isNone:
      populated.gasLimit = some(await signer.estimateGas(populated, BlockTag.pending))

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

  withLock(signer):
    var cancelTx = Transaction(to: sender, value: 0.u256, nonce: some nonce)
    cancelTx = await signer.populateTransaction(cancelTx)
    return await signer.sendTransaction(cancelTx)
