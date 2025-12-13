import pkg/questionable
import pkg/chronicles
import ./basics
import ./errors
import ./provider

export basics
export errors

{.push raises: [].}

type
  Signer* = ref object of RootObj
    populateLock: AsyncLock

template raiseSignerError*(message: string, parent: ref CatchableError = nil) =
  raise newException(SignerError, message, parent)

template convertError(body) =
  try:
    body
  except CancelledError as error:
    raise error
  except ProviderError as error:
    raise error # do not convert provider errors
  except CatchableError as error:
    raiseSignerError(error.msg)

method provider*(
  signer: Signer): Provider {.base, gcsafe, raises: [SignerError].} =
  doAssert false, "not implemented"

method getAddress*(
    signer: Signer
): Future[Address] {.
    base, async: (raises: [ProviderError, SignerError, CancelledError])
.} =
  doAssert false, "not implemented"

method signMessage*(
    signer: Signer, message: seq[byte]
): Future[seq[byte]] {.base, async: (raises: [SignerError, CancelledError]).} =
  doAssert false, "not implemented"

method sendTransaction*(
    signer: Signer, transaction: Transaction
): Future[TransactionResponse] {.
    base, async: (raises: [SignerError, ProviderError, CancelledError])
.} =
  doAssert false, "not implemented"

method getGasPrice*(
    signer: Signer
): Future[UInt256] {.
    base, async: (raises: [ProviderError, SignerError, CancelledError])
.} =
  return await signer.provider.getGasPrice()

method getMaxPriorityFeePerGas*(
    signer: Signer
): Future[UInt256] {.base, async: (raises: [SignerError, CancelledError]).} =
  return await signer.provider.getMaxPriorityFeePerGas()

method getTransactionCount*(
    signer: Signer, blockTag = BlockTag.latest
): Future[UInt256] {.
    base, async: (raises: [SignerError, ProviderError, CancelledError])
.} =
  convertError:
    let address = await signer.getAddress()
    return await signer.provider.getTransactionCount(address, blockTag)

method estimateGas*(
    signer: Signer, transaction: Transaction, blockTag = BlockTag.latest
): Future[UInt256] {.
    base, async: (raises: [SignerError, ProviderError, CancelledError])
.} =
  var transaction = transaction
  transaction.sender = some(await signer.getAddress())
  return await signer.provider.estimateGas(transaction, blockTag)

method getChainId*(
    signer: Signer
): Future[UInt256] {.
    base, async: (raises: [SignerError, ProviderError, CancelledError])
.} =
  return await signer.provider.getChainId()

method getNonce(
    signer: Signer
): Future[UInt256] {.
    base, async: (raises: [SignerError, ProviderError, CancelledError])
.} =
  return await signer.getTransactionCount(BlockTag.pending)

template withLock*(signer: Signer, body: untyped) =
  if signer.populateLock.isNil:
    signer.populateLock = newAsyncLock()

  await signer.populateLock.acquire()
  try:
    body
  finally:
    try:
      signer.populateLock.release()
    except AsyncLockError as e:
      raiseSignerError e.msg, e

method populateTransaction*(
  signer: Signer,
  transaction: Transaction): Future[Transaction]
  {.base, async: (raises: [CancelledError, ProviderError, SignerError]).} =
  ## Populates a transaction with sender, chainId, gasPrice, nonce, and gasLimit.
  ## NOTE: to avoid async concurrency issues, this routine should be called with
  ## a lock if it is followed by sendTransaction. For reference, see the `send`
  ## function in contract.nim.

  var address: Address
  convertError:
    address = await signer.getAddress()

  if sender =? transaction.sender and sender != address:
    raiseSignerError("from address mismatch")
  if chainId =? transaction.chainId and chainId != await signer.getChainId():
    raiseSignerError("chain id mismatch")

  var populated = transaction

  if transaction.sender.isNone:
    populated.sender = some(address)
  if transaction.chainId.isNone:
    populated.chainId = some(await signer.getChainId())

  let blk = await signer.provider.getBlock(BlockTag.latest)

  if baseFeePerGas =? blk.?baseFeePerGas:
    let maxPriorityFeePerGas = transaction.maxPriorityFeePerGas |? (await signer.provider.getMaxPriorityFeePerGas())
    populated.maxPriorityFeePerGas = some(maxPriorityFeePerGas)

    # Multiply by 2 because during times of congestion, baseFeePerGas can increase by 12.5% per block.
    # https://github.com/ethers-io/ethers.js/discussions/3601#discussioncomment-4461273
    let maxFeePerGas = transaction.maxFeePerGas |? (baseFeePerGas * 2 + maxPriorityFeePerGas)
    populated.maxFeePerGas = some(maxFeePerGas)

    populated.gasPrice = none(UInt256)

    trace "EIP-1559 is supported", maxPriorityFeePerGas = maxPriorityFeePerGas, maxFeePerGas = maxFeePerGas
  else:
    populated.gasPrice = some(transaction.gasPrice |? (await signer.getGasPrice()))
    populated.maxFeePerGas = none(UInt256)
    populated.maxPriorityFeePerGas = none(UInt256)
    trace "EIP-1559 is not supported", gasPrice = populated.gasPrice

  if transaction.nonce.isNone and transaction.gasLimit.isNone:
    # when both nonce and gasLimit are not populated, we must ensure getNonce is
    # followed by an estimateGas so we can determine if there was an error. If
    # there is an error, the nonce must be decreased to prevent nonce gaps and
    # stuck transactions
    populated.nonce = some(await signer.getNonce())
    try:
      populated.gasLimit = some(await signer.estimateGas(populated, BlockTag.pending))
    except EstimateGasError as e:
      raise e
    except ProviderError as e:
      raiseSignerError(e.msg)

  else:
    if transaction.nonce.isNone:
      let nonce = await signer.getNonce()
      populated.nonce = some nonce
    if transaction.gasLimit.isNone:
      populated.gasLimit = some(await signer.estimateGas(populated, BlockTag.pending))

  doAssert populated.nonce.isSome, "nonce not populated!"

  return populated

method cancelTransaction*(
  signer: Signer,
  tx: Transaction
): Future[TransactionResponse] {.base, async: (raises: [SignerError, CancelledError, ProviderError]).} =
  # cancels a transaction by sending with a 0-valued transaction to ourselves
  # with the failed tx's nonce

  without sender =? tx.sender:
    raiseSignerError "transaction must have sender"
  without nonce =? tx.nonce:
    raiseSignerError "transaction must have nonce"

  withLock(signer):
    convertError:
      var cancelTx = Transaction(to: sender, value: 0.u256, nonce: some nonce)
      cancelTx = await signer.populateTransaction(cancelTx)
      return await signer.sendTransaction(cancelTx)
