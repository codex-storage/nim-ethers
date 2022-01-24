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

method getTransactionCount*(signer: Signer,
                            blockTag = BlockTag.latest):
                           Future[UInt256] {.base, async.} =
  let address = await signer.getAddress()
  return await signer.provider.getTransactionCount(address, blockTag)

method estimateGas*(signer: Signer,
                    transaction: Transaction): Future[UInt256] {.base, async.} =
  var transaction = transaction
  transaction.sender = some(await signer.getAddress)
  return await signer.provider.estimateGas(transaction)
