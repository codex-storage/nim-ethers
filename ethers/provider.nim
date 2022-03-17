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
  LogHandler* = proc(log: Log) {.gcsafe, upraises:[].}
  Topic* = array[32, byte]
  Block* = object
    number*: UInt256
    timestamp*: UInt256
    hash*: array[32, byte]

method getBlockNumber*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method getBlock*(provider: Provider, tag: BlockTag): Future[?Block] {.base.} =
  doAssert false, "not implemented"

method call*(provider: Provider, tx: Transaction): Future[seq[byte]] {.base.} =
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

method unsubscribe*(subscription: Subscription) {.base, async.} =
  doAssert false, "not implemented"
