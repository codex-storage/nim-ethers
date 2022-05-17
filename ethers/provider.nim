import ./basics
import ./transaction
import ./blocktag

export basics
export transaction
export blocktag

push: {.upraises: [].}

type
  Provider* = ref object of RootObj
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
    blockHash*: BlockHash
    transactionHash*: TransactionHash
    logs*: seq[Log]
    blockNumber*: ?UInt256
    cumulativeGasUsed*: UInt256
    status*: TransactionStatus
  LogHandler* = proc(log: Log) {.gcsafe, upraises:[].}
  BlockHandler* = proc(blck: Block) {.gcsafe, upraises:[].}
  Topic* = array[32, byte]
  Block* = object
    number*: UInt256
    timestamp*: UInt256
    hash*: array[32, byte]

const DEFAULT_CONFIRMATIONS* {.intdefine.} = 12
const RECEIPT_TIMEOUT_BLKS* {.intdefine.} = 50 # in blocks
const RECEIPT_POLLING_INTERVAL* {.intdefine.} = 1 # in seconds

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
