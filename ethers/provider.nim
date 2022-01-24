import ./basics
import ./transaction
import ./blocktag

export basics
export transaction
export blocktag

push: {.upraises: [].}

type
  Provider* = ref object of RootObj

method getBlockNumber*(provider: Provider): Future[UInt256] {.base.} =
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
