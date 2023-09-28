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

type SignerError* = object of EthersError

template raiseSignerError(message: string, parent: ref ProviderError = nil) =
  raise newException(SignerError, message, parent)

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
  return await signer.provider.estimateGas(transaction)

method getChainId*(signer: Signer): Future[UInt256] {.base, gcsafe.} =
  signer.provider.getChainId()

method getNonce(signer: Signer): Future[UInt256] {.base, gcsafe, async.} =
  var nonce = await signer.getTransactionCount(BlockTag.pending)
  
  if lastSeen =? signer.lastSeenNonce and lastSeen >= nonce:
    nonce = (lastSeen + 1.u256)
  signer.lastSeenNonce = some nonce
  
  return nonce

method updateNonce*(signer: Signer, nonce: ?UInt256) {.base, gcsafe.} =
  without nonce =? nonce:
    return

  without lastSeen =? signer.lastSeenNonce:
    signer.lastSeenNonce = some nonce
    return

  if nonce > lastSeen:
    signer.lastSeenNonce = some nonce

method cancelTransaction(
  signer: Signer,
  tx: Transaction
): Future[TransactionResponse] {.async, base.} =
  # cancels a transaction by sending with a 0-valued transaction to ourselves
  # with the failed tx's nonce

  without sender =? tx.sender:
    raiseSignerError "transaction must have sender"
  if sender != await signer.getAddress():
    raiseSignerError "can only cancel a tx this signer has sent"
  without nonce =? tx.nonce:
    raiseSignerError "transaction must have nonce"

  var cancelTx = tx
  cancelTx.to = sender
  cancelTx.value = 0.u256
  cancelTx.nonce = some nonce
  try:
    cancelTx.gasLimit = some(await signer.estimateGas(cancelTx))
  except ProviderError:
    warn "failed to estimate gas for cancellation tx, sending anyway",
      tx = $cancelTx
    discard

  trace "cancelling transaction to prevent stuck transactions", nonce
  return await signer.sendTransaction(cancelTx)

method populateTransaction*(signer: Signer,
                            transaction: Transaction,
                            cancelOnEstimateGasError = false):
                           Future[Transaction] {.base, async.} =

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
  if transaction.nonce.isNone:
    populated.nonce = some(await signer.getNonce())
  if transaction.gasLimit.isNone:
    try:
      populated.gasLimit = some(await signer.estimateGas(populated))
    except ProviderError as e:
      # send a 0-valued transaction with the errored nonce to prevent stuck txs
      discard await signer.cancelTransaction(populated)
      raiseSignerError "Estimate gas failed -- A cancellation transaction " &
        "has been sent to prevent stuck transactions. See parent exception " &
        "for revert reason.", e

  return populated
