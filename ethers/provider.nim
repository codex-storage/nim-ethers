import ./basics

export basics

type
  Provider* = ref object of RootObj

method getBlockNumber*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"
