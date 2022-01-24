import ./basics
import ./provider

export basics

type Signer* = ref object of RootObj

method provider*(signer: Signer): Provider {.base.} =
  doAssert false, "not implemented"

method getAddress*(signer: Signer): Future[Address] {.base.} =
  doAssert false, "not implemented"

method getGasPrice*(signer: Signer): Future[UInt256] {.base.} =
  signer.provider.getGasPrice()
