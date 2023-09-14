import ./basics
import ./provider

export basics

type
  Signer* = ref object of RootObj
    lastSeenNonce: ?UInt256

type SignerError* = object of EthersError

template raiseSignerError(message: string) =
  raise newException(SignerError, message)

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

method populateTransaction*(signer: Signer,
                            transaction: Transaction):
                           Future[Transaction] {.base, async.} =

  if sender =? transaction.sender and sender != await signer.getAddress():
    raiseSignerError("from address mismatch")
  if chainId =? transaction.chainId and chainId != await signer.getChainId():
    raiseSignerError("chain id mismatch")

  var populated = transaction

  if transaction.sender.isNone:
    populated.sender = some(await signer.getAddress())
  if transaction.nonce.isNone:
    populated.nonce = some(await signer.getNonce())
  if transaction.chainId.isNone:
    populated.chainId = some(await signer.getChainId())
  if transaction.gasPrice.isNone and (transaction.maxFee.isNone or transaction.maxPriorityFee.isNone):
    populated.gasPrice = some(await signer.getGasPrice())
  if transaction.gasLimit.isNone:
    populated.gasLimit = some(await signer.estimateGas(populated))

  return populated
