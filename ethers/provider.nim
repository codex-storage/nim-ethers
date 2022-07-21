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
    blockHash*: ?BlockHash
    transactionHash*: TransactionHash
    logs*: seq[Log]
    blockNumber*: ?UInt256
    cumulativeGasUsed*: UInt256
    status*: TransactionStatus
  LogHandler* = proc(log: Log) {.gcsafe, upraises:[].}
  BlockHandler* = proc(blck: Block): Future[void] {.gcsafe, upraises:[].}
  Topic* = array[32, byte]
  Block* = object
    number*: ?UInt256
    timestamp*: UInt256
    hash*: array[32, byte]

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

method estimateGas*(provider: Provider,
                    transaction: Transaction): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method getChainId*(provider: Provider): Future[UInt256] {.base.} =
  doAssert false, "not implemented"

method sendRawTransaction*(provider: Provider, rawTransaction: seq[byte]): Future[TransactionResponse] {.base, async.} =
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

# Removed from `confirm` closure and exported so it can be tested.
# Likely there is a better way
func confirmations*(receiptBlk, atBlk: UInt256): UInt256 =
  ## Calculates the number of confirmations between two blocks
  if atBlk < receiptBlk:
    return 0.u256
  else:
    return (atBlk - receiptBlk) + 1 # add 1 for current block

# Removed from `confirm` closure and exported so it can be tested.
# Likely there is a better way
func hasBeenMined*(receipt: TransactionReceipt,
                  atBlock: UInt256,
                  wantedConfirms: int): bool =
  ## Returns true if the transaction receipt has been returned from the node
  ## with a valid block number and block hash and the specified number of
  ## blocks have passed since the tx was mined (confirmations)

  if number =? receipt.blockNumber and
     number > 0 and
    # from ethers.js: "geth-etc" returns receipts before they are ready
    receipt.blockHash.isSome:

    return number.confirmations(atBlock) >= wantedConfirms.u256

  return false

proc confirm*(tx: TransactionResponse,
             wantedConfirms: Positive = EthersDefaultConfirmations,
             timeoutInBlocks: Natural = EthersReceiptTimeoutBlks):
            Future[TransactionReceipt]
            {.async, upraises: [EthersError].} = # raises for clarity
  ## Waits for a transaction to be mined and for the specified number of blocks
  ## to pass since it was mined (confirmations).
  ## A timeout, in blocks, can be specified that will raise an error if too many
  ## blocks have passed without the tx having been mined.

  var subscription: Subscription
  let
    provider = tx.provider
    retFut = newFuture[TransactionReceipt]("wait")

  # used to check for block timeouts
  let startBlock = await provider.getBlockNumber()

  proc newBlock(blk: Block) {.async.} =
    ## subscription callback, called every time a new block event is sent from
    ## the node

    # if ethereum node doesn't include blockNumber in the event
    without blkNum =? blk.number:
      return

    if receipt =? (await provider.getTransactionReceipt(tx.hash)) and
       receipt.hasBeenMined(blkNum, wantedConfirms):
      # fire and forget
      discard subscription.unsubscribe()
      if not retFut.finished:
        retFut.complete(receipt)

    elif timeoutInBlocks > 0:
      let blocksPassed = (blkNum - startBlock) + 1
      if blocksPassed >= timeoutInBlocks.u256:
        discard subscription.unsubscribe()
        if not retFut.finished:
          let message =
            "Transaction was not mined in " & $timeoutInBlocks & " blocks"
          retFut.fail(newException(EthersError, message))

  # If our tx is already mined, return the receipt. Otherwise, check each
  # new block to see if the tx has been mined
  if receipt =? (await provider.getTransactionReceipt(tx.hash)) and
     receipt.hasBeenMined(startBlock, wantedConfirms):
    return receipt
  else:
    subscription = await provider.subscribe(newBlock)
    return (await retFut)

proc confirm*(tx: Future[TransactionResponse],
             wantedConfirms: Positive = EthersDefaultConfirmations,
             timeoutInBlocks: Natural = EthersReceiptTimeoutBlks):
            Future[TransactionReceipt] {.async.} =
  ## Convenience method that allows wait to be chained to a sendTransaction
  ## call, eg:
  ## `await signer.sendTransaction(populated).confirm(3)`

  let txResp = await tx
  return await txResp.confirm(wantedConfirms, timeoutInBlocks)

proc confirm*(tx: Future[?TransactionResponse],
             wantedConfirms: Positive = EthersDefaultConfirmations,
             timeoutInBlocks: Natural = EthersReceiptTimeoutBlks):
            Future[TransactionReceipt] {.async.} =
  ## Convenience method that allows wait to be chained to a contract
  ## transaction, eg:
  ## `await token.connect(signer0)
  ##          .mint(accounts[1], 100.u256)
  ##          .confirm(3)`

  without txResp =? (await tx):
    raise newException(
      EthersError,
      "Transaction hash required. Possibly was a call instead of a send?"
    )

  return await txResp.confirm(wantedConfirms, timeoutInBlocks)
