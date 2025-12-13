import pkg/chronicles
import pkg/serde
import pkg/questionable
import ./basics
import ./transaction
import ./blocktag
import ./errors

export basics
export transaction
export blocktag
export errors

{.push raises: [].}

type
  Provider* = ref object of RootObj
  EstimateGasError* = object of ProviderError
    transaction*: Transaction
  Subscription* = ref object of RootObj
  EventFilter* {.serialize.} = ref object of RootObj
    address*: Address
    topics*: seq[Topic]
  Filter* {.serialize.} = ref object of EventFilter
    fromBlock*: BlockTag
    toBlock*: BlockTag
  FilterByBlockHash* {.serialize.} = ref object of EventFilter
    blockHash*: BlockHash
  Log* {.serialize.} = object
    blockNumber*: BlockNumber
    data*: seq[byte]
    logIndex*: UInt256
    removed*: bool
    address*: Address
    topics*: seq[Topic]
  TransactionHash* = array[32, byte]
  BlockHash* = array[32, byte]
  TransactionStatus* = enum
    Failure = 0,
    Success = 1,
    Invalid = 2
  TransactionResponse* = object
    provider*: Provider
    hash* {.serialize.}: TransactionHash
  TransactionReceipt* {.serialize.} = object
    sender* {.serialize("from"), deserialize("from").}: ?Address
    to*: ?Address
    contractAddress*: ?Address
    transactionIndex*: UInt256
    gasUsed*: UInt256
    logsBloom*: seq[byte]
    blockHash*: ?BlockHash
    transactionHash*: TransactionHash
    logs*: seq[Log]
    blockNumber*: ?BlockNumber
    cumulativeGasUsed*: UInt256
    effectiveGasPrice*: ?UInt256
    status*: TransactionStatus
    transactionType* {.serialize("type"), deserialize("type").}: TransactionType
  LogHandler* = proc(log: Log) {.gcsafe, raises:[].}
  BlockHandler* = proc(blck: Block) {.gcsafe, raises:[].}
  Topic* = array[32, byte]
  Block* {.serialize.} = object
    number*: ?BlockNumber
    timestamp*: UInt256
    hash*: ?BlockHash
    baseFeePerGas* : ?UInt256
    logsBloom*: ?StUint[2048]
  BlockNumber* = UInt256
  PastTransaction* {.serialize.} = object
    blockHash*: BlockHash
    blockNumber*: BlockNumber
    sender* {.serialize("from"), deserialize("from").}: Address
    gas*: UInt256
    gasPrice*: UInt256
    hash*: TransactionHash
    input*: seq[byte]
    nonce*: UInt256
    to*: Address
    transactionIndex*: UInt256
    transactionType* {.serialize("type"), deserialize("type").}: ?TransactionType
    chainId*: ?UInt256
    value*: UInt256
    v*, r*, s*: UInt256

const EthersDefaultConfirmations* {.intdefine.} = 12
const EthersReceiptTimeoutBlks* {.intdefine.} = 50 # in blocks

logScope:
  topics = "ethers provider"

template raiseProviderError(msg: string) =
  raise newException(ProviderError, msg)

func toTransaction*(past: PastTransaction): Transaction =
  Transaction(
    sender: some past.sender,
    to: past.to,
    data: past.input,
    value: past.value,
    nonce: some past.nonce,
    chainId: past.chainId,
    gasPrice: some past.gasPrice,
    gasLimit: some past.gas,
    transactionType: past.transactionType
  )

method getBlockNumber*(
    provider: Provider
): Future[UInt256] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method getBlock*(
    provider: Provider, tag: BlockTag
): Future[?Block] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method call*(
    provider: Provider, tx: Transaction, blockTag = BlockTag.latest
): Future[seq[byte]] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method getGasPrice*(
    provider: Provider
): Future[UInt256] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method getMaxPriorityFeePerGas*(
    provider: Provider
): Future[UInt256] {.base, async: (raises: [CancelledError]).} =
  doAssert false, "not implemented"

method getTransactionCount*(
    provider: Provider, address: Address, blockTag = BlockTag.latest
): Future[UInt256] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method getTransaction*(
    provider: Provider, txHash: TransactionHash
): Future[?PastTransaction] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method getTransactionReceipt*(
    provider: Provider, txHash: TransactionHash
): Future[?TransactionReceipt] {.
    base, async: (raises: [ProviderError, CancelledError])
.} =
  doAssert false, "not implemented"

method sendTransaction*(
    provider: Provider, rawTransaction: seq[byte]
): Future[TransactionResponse] {.
    base, async: (raises: [ProviderError, CancelledError])
.} =
  doAssert false, "not implemented"

method getLogs*(
    provider: Provider, filter: EventFilter
): Future[seq[Log]] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method estimateGas*(
    provider: Provider, transaction: Transaction, blockTag = BlockTag.latest
): Future[UInt256] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method getChainId*(
    provider: Provider
): Future[UInt256] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method subscribe*(
    provider: Provider, filter: EventFilter, callback: LogHandler
): Future[Subscription] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method subscribe*(
    provider: Provider, callback: BlockHandler
): Future[Subscription] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method unsubscribe*(
    subscription: Subscription
) {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

method isSyncing*(provider: Provider): Future[bool] {.base, async: (raises: [ProviderError, CancelledError]).} =
  doAssert false, "not implemented"

proc replay*(
    provider: Provider, tx: Transaction, blockNumber: UInt256
) {.async: (raises: [ProviderError, CancelledError]).} =
  # Replay transaction at block. Useful for fetching revert reasons, which will
  # be present in the raised error message. The replayed block number should
  # include the state of the chain in the block previous to the block in which
  # the transaction was mined. This means that transactions that were mined in
  # the same block BEFORE this transaction will not have their state transitions
  # included in the replay.
  # More information: https://snakecharmers.ethereum.org/web3py-revert-reason-parsing/
  trace "replaying transaction", gasLimit = tx.gasLimit, tx = $tx
  discard await provider.call(tx, BlockTag.init(blockNumber))

proc ensureSuccess(
    provider: Provider, receipt: TransactionReceipt
) {.async: (raises: [ProviderError, CancelledError]).} =
  ## If the receipt.status is Failed, the tx is replayed to obtain a revert
  ## reason, after which a ProviderError with the revert reason is raised.
  ## If no revert reason was obtained

  # TODO: handle TransactionStatus.Invalid?
  if receipt.status != TransactionStatus.Failure:
    return

  without blockNumber =? receipt.blockNumber and
          pastTx =? await provider.getTransaction(receipt.transactionHash):
    raiseProviderError("Transaction reverted with unknown reason")

  try:
    await provider.replay(pastTx.toTransaction, blockNumber)
    raiseProviderError("Transaction reverted with unknown reason")
  except ProviderError as error:
    raise error

proc confirm*(
  tx: TransactionResponse,
  confirmations = EthersDefaultConfirmations,
  timeout = EthersReceiptTimeoutBlks): Future[TransactionReceipt]
  {.async: (raises: [CancelledError, ProviderError, EthersError]).} =

  ## Waits for a transaction to be mined and for the specified number of blocks
  ## to pass since it was mined (confirmations). The number of confirmations
  ## includes the block in which the transaction was mined.
  ## A timeout, in blocks, can be specified that will raise an error if too many
  ## blocks have passed without the tx having been mined.

  assert confirmations > 0

  var blockNumber = await tx.provider.getBlockNumber()
  let blockEvent = newAsyncEvent()
  blockEvent.fire()

  proc onBlock(blck: Block) =
    if number =? blck.number:
      blockNumber = number
      blockEvent.fire()

  let subscription = await tx.provider.subscribe(onBlock)

  let finish = blockNumber + timeout.u256

  try:
    var receipt: ?TransactionReceipt

    while true:
      await blockEvent.wait()
      blockEvent.clear()

      if blockNumber >= finish:
        raise newException(EthersError, "tx not mined before timeout")

      if receipt.?blockNumber.isNone:
        receipt = await tx.provider.getTransactionReceipt(tx.hash)

      without receipt =? receipt and txBlockNumber =? receipt.blockNumber:
        continue

      if txBlockNumber + confirmations.u256 <= blockNumber + 1:
        await tx.provider.ensureSuccess(receipt)
        return receipt
  finally:
    await subscription.unsubscribe()

proc confirm*(
  tx: Future[TransactionResponse],
  confirmations: int = EthersDefaultConfirmations,
  timeout: int = EthersReceiptTimeoutBlks): Future[TransactionReceipt] {.async: (raises: [CancelledError, EthersError]).} =
  ## Convenience method that allows wait to be chained to a sendTransaction
  ## call, eg:
  ## `await signer.sendTransaction(populated).confirm(3)`
  try:
    let txResp = await tx
    return await txResp.confirm(confirmations, timeout)
  except CancelledError as e:
    raise e
  except EthersError as e:
    raise e
  except CatchableError as e:
    raise newException(
      EthersError,
      "Error when trying to confirm the provider transaction: " & e.msg
    )

method close*(
    provider: Provider
) {.base, async: (raises: [ProviderError, CancelledError]).} =
  discard
