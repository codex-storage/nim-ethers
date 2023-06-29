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
  Filter* = object
    address*: Address
    topics*: seq[Topic]
  Log* = object
    data*: seq[byte]
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

const EthersDefaultConfirmations* {.intdefine.} = 12
const EthersReceiptTimeoutBlks* {.intdefine.} = 50 # in blocks

method getBlockNumber*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method getBlock*(provider: Provider, tag: BlockTag): Future[?Block] {.base.} =
  doAssert false, "not implemented"

method call*(provider: Provider,
             tx: Transaction,
             blockTag = BlockTag.latest): Future[seq[byte]] {.base.} =
  doAssert false, "not implemented"

method getGasPrice*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method getTransactionCount*(provider: Provider,
                            address: Address,
                            blockTag = BlockTag.latest):
                           Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method getTransactionReceipt*(provider: Provider,
                            txHash: TransactionHash):
                           Future[?TransactionReceipt] {.base.} =
  doAssert false, "not implemented"

method sendTransaction*(provider: Provider,
                        rawTransaction: seq[byte]):
                       Future[TransactionResponse] {.base.} =
  doAssert false, "not implemented"

method estimateGas*(provider: Provider,
                    transaction: Transaction): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method getChainId*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method subscribe*(provider: Provider,
                  filter: Filter,
                  callback: LogHandler):
                 Future[Subscription] {.base.} =
  doAssert false, "not implemented"

method subscribe*(provider: Provider,
                  callback: BlockHandler):
                 Future[Subscription] {.base.} =
  doAssert false, "not implemented"

method unsubscribe*(subscription: Subscription) {.base, async.} =
  doAssert false, "not implemented"

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
