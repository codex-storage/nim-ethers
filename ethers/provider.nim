import ./basics
import ./transaction

export basics
export transaction

push: {.upraises: [].}

type
  Provider* = ref object of RootObj

method getBlockNumber*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method call*(provider: Provider, tx: Transaction): Future[seq[byte]] {.base.} =
  doAssert false, "not implemented"
