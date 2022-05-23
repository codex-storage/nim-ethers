import std/json
import std/tables
import std/uri
import pkg/json_rpc/rpcclient
import ../basics
import ../provider
import ../signer
import ./jsonrpc/rpccalls
import ./jsonrpc/conversions

export basics
export provider
export conversions

push: {.upraises: [].}

type
  JsonRpcProvider* = ref object of Provider
    client: Future[RpcClient]
    subscriptions: Table[JsonNode, SubscriptionHandler]
  JsonRpcSubscription = ref object of Subscription
    provider: JsonRpcProvider
    id: JsonNode
  JsonRpcSigner* = ref object of Signer
    provider: JsonRpcProvider
    address: ?Address
  JsonRpcProviderError* = object of EthersError
  SubscriptionHandler = proc(id, arguments: JsonNode): Future[void] {.gcsafe, upraises:[].}

template raiseProviderError(message: string) =
  raise newException(JsonRpcProviderError, message)

# Provider

const defaultUrl = "http://localhost:8545"

proc connect(_: type RpcClient, url: string): Future[RpcClient] {.async.} =
  case parseUri(url).scheme
  of "ws", "wss":
    let client = newRpcWebSocketClient()
    await client.connect(url)
    return client
  else:
    let client = newRpcHttpClient()
    await client.connect(url)
    return client

proc connect(provider: JsonRpcProvider, url: string) =

  proc getSubscriptionHandler(id: JsonNode): ?SubscriptionHandler =
    try:
      if provider.subscriptions.hasKey(id):
        provider.subscriptions[id].some
      else:
        SubscriptionHandler.none
    except Exception:
      SubscriptionHandler.none

  proc handleSubscription(arguments: JsonNode) {.upraises: [].} =
    if id =? arguments["subscription"].catch and
       handler =? getSubscriptionHandler(id):
      # fire and forget
      discard handler(id, arguments)

  proc subscribe: Future[RpcClient] {.async.} =
    let client = await RpcClient.connect(url)
    client.setMethodHandler("eth_subscription", handleSubscription)
    return client

  provider.client = subscribe()

proc new*(_: type JsonRpcProvider, url=defaultUrl): JsonRpcProvider =
  let provider = JsonRpcProvider()
  provider.connect(url)
  provider

proc send*(provider: JsonRpcProvider,
           call: string,
           arguments: seq[JsonNode] = @[]): Future[JsonNode] {.async.} =
  let client = await provider.client
  return await client.call(call, %arguments)

proc listAccounts*(provider: JsonRpcProvider): Future[seq[Address]] {.async.} =
  let client = await provider.client
  return await client.eth_accounts()

proc getSigner*(provider: JsonRpcProvider): JsonRpcSigner =
  JsonRpcSigner(provider: provider)

proc getSigner*(provider: JsonRpcProvider, address: Address): JsonRpcSigner =
  JsonRpcSigner(provider: provider, address: some address)

method getBlockNumber*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  let client = await provider.client
  return await client.eth_blockNumber()

method getBlock*(provider: JsonRpcProvider,
                 tag: BlockTag): Future[?Block] {.async.} =
  let client = await provider.client
  return await client.eth_getBlockByNumber(tag, false)

method call*(provider: JsonRpcProvider,
             tx: Transaction,
             blockTag = BlockTag.latest): Future[seq[byte]] {.async.} =
  let client = await provider.client
  return await client.eth_call(tx, blockTag)

method getGasPrice*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  let client = await provider.client
  return await client.eth_gasprice()

method getTransactionCount*(provider: JsonRpcProvider,
                            address: Address,
                            blockTag = BlockTag.latest):
                           Future[UInt256] {.async.} =
  let client = await provider.client
  return await client.eth_getTransactionCount(address, blockTag)

method getTransactionReceipt*(provider: JsonRpcProvider,
                            txHash: TransactionHash):
                           Future[?TransactionReceipt] {.async.} =
  let client = await provider.client
  return await client.eth_getTransactionReceipt(txHash)

method estimateGas*(provider: JsonRpcProvider,
                    transaction: Transaction): Future[UInt256] {.async.} =
  let client = await provider.client
  return await client.eth_estimateGas(transaction)

method getChainId*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  let client = await provider.client
  try:
    return await client.eth_chainId()
  except CatchableError:
    return parse(await client.net_version(), UInt256)

proc subscribe(provider: JsonRpcProvider,
               name: string,
               filter: ?Filter,
               handler: SubscriptionHandler): Future[Subscription] {.async.} =
  let client = await provider.client
  doAssert client of RpcWebSocketClient, "subscriptions require websockets"

  let id = await client.eth_subscribe(name, filter)
  provider.subscriptions[id] = handler

  return JsonRpcSubscription(id: id, provider: provider)

method subscribe*(provider: JsonRpcProvider,
                  filter: Filter,
                  callback: LogHandler):
                 Future[Subscription] {.async.} =
  proc handler(id, arguments: JsonNode) {.async.} =
    if log =? Log.fromJson(arguments["result"]).catch:
      callback(log)
  return await provider.subscribe("logs", filter.some, handler)

method subscribe*(provider: JsonRpcProvider,
                  callback: BlockHandler):
                 Future[Subscription] {.async.} =
  proc handler(id, arguments: JsonNode) {.async.} =
    if blck =? Block.fromJson(arguments["result"]).catch:
      await callback(blck)
  return await provider.subscribe("newHeads", Filter.none, handler)

method unsubscribe*(subscription: JsonRpcSubscription) {.async.} =
  let provider = subscription.provider
  provider.subscriptions.del(subscription.id)
  let client = await provider.client
  discard await client.eth_unsubscribe(subscription.id)

# Signer

method provider*(signer: JsonRpcSigner): Provider =
  signer.provider

method getAddress*(signer: JsonRpcSigner): Future[Address] {.async.} =
  if address =? signer.address:
    return address

  let accounts = await signer.provider.listAccounts()
  if accounts.len > 0:
    return accounts[0]

  raiseProviderError "no address found"

method signMessage*(signer: JsonRpcSigner,
                    message: seq[byte]): Future[seq[byte]] {.async.} =
  let client = await signer.provider.client
  let address = await signer.getAddress()
  return await client.eth_sign(address, message)

method sendTransaction*(signer: JsonRpcSigner,
                        transaction: Transaction): Future[TransactionResponse] {.async.} =
  let
    client = await signer.provider.client
    hash = await client.eth_sendTransaction(transaction)

  return TransactionResponse(hash: hash, provider: signer.provider)


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
func hasBeenMined*(receipt: ?TransactionReceipt,
                  atBlock: UInt256,
                  wantedConfirms: int): bool =
  ## Returns true if the transaction receipt has been returned from the node
  ## with a valid block number and block hash and the specified number of
  ## blocks have passed since the tx was mined (confirmations)

  if receipt.isSome and
    receipt.get.blockNumber.isSome and
    receipt.get.blockNumber.get > 0 and
    # from ethers.js: "geth-etc" returns receipts before they are ready
    receipt.get.blockHash.isSome:

    let receiptBlock = receipt.get.blockNumber.get
    return receiptBlock.confirmations(atBlock) >= wantedConfirms.u256

  return false

proc confirm*(tx: TransactionResponse,
             wantedConfirms: Positive = EthersDefaultConfirmations,
             timeoutInBlocks: Natural = EthersReceiptTimeoutBlks):
            Future[TransactionReceipt]
            {.async, upraises: [JsonRpcProviderError].} = # raises for clarity
  ## Waits for a transaction to be mined and for the specified number of blocks
  ## to pass since it was mined (confirmations).
  ## A timeout, in blocks, can be specified that will raise a
  ## JsonRpcProviderError if too many blocks have passed without the tx
  ## having been mined.
  ## Note: this method requires that the JsonRpcProvider client connects
  ## using RpcWebSocketClient, otherwise it will raise a Defect.

  var subscription: JsonRpcSubscription
  let
    provider = JsonRpcProvider(tx.provider)
    retFut = newFuture[TransactionReceipt]("wait")

  # used to check for block timeouts
  let startBlock = await provider.getBlockNumber()

  proc newBlock(blk: Block) {.async.} =
    ## subscription callback, called every time a new block event is sent from
    ## the node

    # if ethereum node doesn't include blockNumber in the event
    without blkNum =? blk.number:
      return

    let receipt = await provider.getTransactionReceipt(tx.hash)
    if receipt.hasBeenMined(blkNum, wantedConfirms):
      # fire and forget
      discard subscription.unsubscribe()
      if not retFut.finished:
        retFut.complete(receipt.get)

    elif timeoutInBlocks > 0:
      let blocksPassed = (blkNum - startBlock) + 1
      if blocksPassed >= timeoutInBlocks.u256:
        discard subscription.unsubscribe()
        if not retFut.finished:
          let message =
            "Transaction was not mined in " & $timeoutInBlocks & " blocks"
          retFut.fail(newException(JsonRpcProviderError, message))

  # If our tx is already mined, return the receipt. Otherwise, check each
  # new block to see if the tx has been mined
  let receipt = await provider.getTransactionReceipt(tx.hash)
  if receipt.hasBeenMined(startBlock, wantedConfirms):
    return receipt.get
  else:
    let sub = await provider.subscribe(newBlock)
    subscription = JsonRpcSubscription(sub)
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
    raiseProviderError("Transaction hash required. Possibly was a call instead of a send?")

  return await txResp.confirm(wantedConfirms, timeoutInBlocks)
