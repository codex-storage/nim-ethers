import pkg/questionable
import ./basics
import ./provider

export basics

{.push raises: [].}

type
  Signer* = ref object of RootObj
    lastSeenNonce: ?UInt256
    populateLock: AsyncLock
  SignerError* = object of ProviderError
  EstimateGasError* = object of SignerError
    transaction*: Transaction

template raiseSignerError(message: string, parent: ref ProviderError = nil) =
  raise newException(SignerError, message, parent)

proc raiseEstimateGasError(
  transaction: Transaction,
  parent: ref ProviderError = nil
) {.raises: [EstimateGasError] .} =
  let e = (ref EstimateGasError)(
    msg: "Estimate gas failed",
    transaction: transaction,
    parent: parent)
  raise e

template convertError(body) =
  try:
    body
  except EthersError as error:
    raiseSignerError(error.msg)
  except CatchableError as error:
    raiseSignerError(error.msg)

method provider*(
  signer: Signer): Provider {.base, gcsafe, raises: [SignerError].} =
  doAssert false, "not implemented"

method getAddress*(
  signer: Signer): Future[Address] {.base, async.} =

  doAssert false, "not implemented"

method signMessage*(
  signer: Signer,
  message: seq[byte]): Future[seq[byte]] {.base, async: (raises: [SignerError]).} =

  doAssert false, "not implemented"

method sendTransaction*(
  signer: Signer,
  transaction: Transaction): Future[TransactionResponse]
  {.base, async.} =

  doAssert false, "not implemented"

method getGasPrice*(
  signer: Signer): Future[UInt256] {.base, gcsafe, async: (raises: [SignerError]).} =

  convertError:
    return await signer.provider.getGasPrice()

method getTransactionCount*(
  signer: Signer,
  blockTag = BlockTag.latest): Future[UInt256]
  {.base, async: (raises:[SignerError]).} =

  convertError:
    let address = await signer.getAddress()
    return await signer.provider.getTransactionCount(address, blockTag)

method estimateGas*(
  signer: Signer,
  transaction: Transaction,
  blockTag = BlockTag.latest): Future[UInt256]
  {.base, async: (raises:[SignerError]).} =

  var transaction = transaction
  var address: Address

  convertError:
    address = await signer.getAddress

  transaction.`from` = some(address)
  try:
    return await signer.provider.estimateGas(transaction)
  except ProviderError as e:
    raiseEstimateGasError transaction, e

method getChainId*(
  signer: Signer): Future[UInt256] {.base, async: (raises: [SignerError]).} =

  convertError:
    return await signer.provider.getChainId()

method getNonce(
  signer: Signer): Future[UInt256] {.base, async: (raises: [SignerError]).} =

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

method populateTransaction*(
  signer: Signer,
  transaction: Transaction): Future[Transaction]
  {.base, async: (raises: [CancelledError, AsyncLockError, SignerError]).} =

  echo "[signer.populatetransaction] signer type: ", typeof signer
  if sender =? transaction.`from` and sender != await signer.getAddress():
    raiseSignerError("from address mismatch")
  if chainId =? transaction.chainId and chainId != await signer.getChainId():
    raiseSignerError("chain id mismatch")

  if signer.populateLock.isNil:
    signer.populateLock = newAsyncLock()

  await signer.populateLock.acquire()

  var populated = transaction

  try:
    if transaction.`from`.isNone:
      populated.`from` = some(await signer.getAddress())
    if transaction.chainId.isNone:
      populated.chainId = some(await signer.getChainId())
    if transaction.gasPrice.isNone and (transaction.maxFee.isNone or transaction.maxPriorityFee.isNone):
      populated.gasPrice = some(await signer.getGasPrice())

    if transaction.nonce.isNone and transaction.gasLimit.isNone:
      # when both nonce and gasLimit are not populated, we must ensure getNonce is
      # followed by an estimateGas so we can determine if there was an error. If
      # there is an error, the nonce must be decreased to prevent nonce gaps and
      # stuck transactions
      populated.nonce = some(await signer.getNonce())
      try:
        populated.gasLimit = some(await signer.estimateGas(populated))
      except ProviderError as e:
        signer.decreaseNonce()
        raiseSignerError(e.msg)
      except EstimateGasError as e:
        signer.decreaseNonce()
        raise e

    else:
      if transaction.nonce.isNone:
        populated.nonce = some(await signer.getNonce())
      if transaction.gasLimit.isNone:
        populated.gasLimit = some(await signer.estimateGas(populated))

  finally:
    signer.populateLock.release()

  return populated

method cancelTransaction*(
  signer: Signer,
  tx: Transaction
): Future[TransactionResponse] {.base, async: (raises: [SignerError]).} =
  # cancels a transaction by sending with a 0-valued transaction to ourselves
  # with the failed tx's nonce

  without sender =? tx.`from`:
    raiseSignerError "transaction must have sender"
  without nonce =? tx.nonce:
    raiseSignerError "transaction must have nonce"

  var cancelTx = Transaction(to: sender, value: 0.u256, nonce: some nonce)
  convertError:
    cancelTx = await signer.populateTransaction(cancelTx)
    return await signer.sendTransaction(cancelTx)
