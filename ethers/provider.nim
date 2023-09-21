import pkg/chronicles
import ./basics
import ./transaction
import ./blocktag

export basics
export transaction
export blocktag

push: {.upraises: [].}

type
  Provider* = ref object of RootObj
  ProviderError* = object of EthersError
  Subscription* = ref object of RootObj
  EventFilter* = ref object of RootObj
    address*: Address
    topics*: seq[Topic]
  Filter* = ref object of EventFilter
    fromBlock*: BlockTag
    toBlock*: BlockTag
  FilterByBlockHash* = ref object of EventFilter
    blockHash*: BlockHash
  Log* = object
    blockNumber*: UInt256
    data*: seq[byte]
    logIndex*: UInt256
    removed*: bool
    topics*: seq[Topic]
  TransactionHash* = array[32, byte]
  BlockHash* = array[32, byte]
  TransactionStatus* = enum
    Failure = 0,
    Success = 1,
    Invalid = 2
  TransactionResponse* = object
    provider*: Provider
    hash*: TransactionHash
  TransactionReceipt* = object
    sender*: ?Address
    to*: ?Address
    contractAddress*: ?Address
    transactionIndex*: UInt256
    gasUsed*: UInt256
    logsBloom*: seq[byte]
    blockHash*: ?BlockHash
    transactionHash*: TransactionHash
    logs*: seq[Log]
    blockNumber*: ?UInt256
    cumulativeGasUsed*: UInt256
    status*: TransactionStatus
  LogHandler* = proc(log: Log) {.gcsafe, upraises:[].}
  BlockHandler* = proc(blck: Block) {.gcsafe, upraises:[].}
  Topic* = array[32, byte]
  Block* = object
    number*: ?UInt256
    timestamp*: UInt256
    hash*: ?BlockHash
  PastTransaction* = object
    blockHash*: BlockHash
    blockNumber*: UInt256
    sender*: Address
    gas*: UInt256
    gasPrice*: UInt256
    hash*: TransactionHash
    input*: seq[byte]
    nonce*: UInt256
    to*: Address
    transactionIndex*: UInt256
    value*: UInt256
    v*, r*, s*         : UInt256

const EthersDefaultConfirmations* {.intdefine.} = 12
const EthersReceiptTimeoutBlks* {.intdefine.} = 50 # in blocks

logScope:
  topics = "ethers provider"

template raiseProviderError(message: string) =
  raise newException(ProviderError, message)

method getBlockNumber*(provider: Provider): Future[UInt256] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getBlock*(provider: Provider, tag: BlockTag): Future[?Block] {.base, gcsafe.} =
  doAssert false, "not implemented"

method call*(provider: Provider,
             tx: PastTransaction,
             blockTag = BlockTag.latest): Future[seq[byte]] {.base, gcsafe.} =
  doAssert false, "not implemented"

method call*(provider: Provider,
             tx: Transaction,
             blockTag = BlockTag.latest): Future[seq[byte]] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getGasPrice*(provider: Provider): Future[UInt256] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getTransactionCount*(provider: Provider,
                            address: Address,
                            blockTag = BlockTag.latest):
                           Future[UInt256] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getTransaction*(provider: Provider,
                       txHash: TransactionHash):
                      Future[?PastTransaction] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getTransactionReceipt*(provider: Provider,
                            txHash: TransactionHash):
                           Future[?TransactionReceipt] {.base, gcsafe.} =
  doAssert false, "not implemented"

method sendTransaction*(provider: Provider,
                        rawTransaction: seq[byte]):
                       Future[TransactionResponse] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getLogs*(provider: Provider,
                filter: EventFilter): Future[seq[Log]] {.base, gcsafe.} =
  doAssert false, "not implemented"

method estimateGas*(provider: Provider,
                    transaction: Transaction): Future[UInt256] {.base, gcsafe.} =
  doAssert false, "not implemented"

method getChainId*(provider: Provider): Future[UInt256] {.base, gcsafe.} =
  doAssert false, "not implemented"

method subscribe*(provider: Provider,
                  filter: EventFilter,
                  callback: LogHandler):
                 Future[Subscription] {.base, gcsafe.} =
  doAssert false, "not implemented"

method subscribe*(provider: Provider,
                  callback: BlockHandler):
                 Future[Subscription] {.base, gcsafe.} =
  doAssert false, "not implemented"

method unsubscribe*(subscription: Subscription) {.base, async.} =
  doAssert false, "not implemented"

proc replay*(provider: Provider, tx: PastTransaction, blockNumber: UInt256) {.async.} =
  # Replay transaction at block. Useful for fetching revert reasons, which will
  # be present in the raised error message. The replayed block number should
  # include the state of the chain in the block previous to the block in which
  # the transaction was mined. This means that transactions that were mined in
  # the same block BEFORE this transaction will not have their state transitions
  # included in the replay.
  # More information: https://snakecharmers.ethereum.org/web3py-revert-reason-parsing/
  discard await provider.call(tx, BlockTag.init(blockNumber - 1))

method getRevertReason*(
  provider: Provider,
  receipt: TransactionReceipt
): Future[?string] {.base, async.} =

  if receipt.status != TransactionStatus.Failure:
    raiseProviderError "cannot get revert reason, transaction not failed"

  without blockNumber =? receipt.blockNumber or
          transaction =? await provider.getTransaction(receipt.transactionHash):
    return none string

  try:
    await provider.replay(transaction, blockNumber)
    return none string
  except ProviderError as e:
    # should contain the revert reason
    return some e.msg

proc confirm*(tx: TransactionResponse,
              confirmations = EthersDefaultConfirmations,
              timeout = EthersReceiptTimeoutBlks):
             Future[TransactionReceipt]
             {.async, upraises: [EthersError].} =
  ## Waits for a transaction to be mined and for the specified number of blocks
  ## to pass since it was mined (confirmations).
  ## A timeout, in blocks, can be specified that will raise an error if too many
  ## blocks have passed without the tx having been mined.

  var blockNumber: UInt256
  let blockEvent = newAsyncEvent()

  proc onBlockNumber(number: UInt256) =
    blockNumber = number
    blockEvent.fire()

  proc onBlock(blck: Block) =
    if number =? blck.number:
      onBlockNumber(number)

  onBlockNumber(await tx.provider.getBlockNumber())
  let subscription = await tx.provider.subscribe(onBlock)

  let finish = blockNumber + timeout.u256
  var receipt: ?TransactionReceipt

  while true:
    await blockEvent.wait()
    blockEvent.clear()

    if blockNumber >= finish:
      await subscription.unsubscribe()
      raise newException(EthersError, "tx not mined before timeout")

    if receipt.?blockNumber.isNone:
      receipt = await tx.provider.getTransactionReceipt(tx.hash)

    without receipt =? receipt and txBlockNumber =? receipt.blockNumber:
      continue

    if txBlockNumber + confirmations.u256 <= blockNumber + 1:
      await subscription.unsubscribe()
      return receipt

proc confirm*(tx: Future[TransactionResponse],
             confirmations: int = EthersDefaultConfirmations,
             timeout: int = EthersReceiptTimeoutBlks):
            Future[TransactionReceipt] {.async.} =
  ## Convenience method that allows wait to be chained to a sendTransaction
  ## call, eg:
  ## `await signer.sendTransaction(populated).confirm(3)`

  let txResp = await tx
  return await txResp.confirm(confirmations, timeout)

method close*(provider: Provider) {.async, base.} =
  discard
