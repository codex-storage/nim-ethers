import ./basics

export basics

type Signer* = ref object of RootObj

method getAddress*(signer: Signer): Future[Address] {.base, async.} =
  doAssert false, "not implemented"
