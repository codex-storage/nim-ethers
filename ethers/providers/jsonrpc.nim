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
  SubscriptionHandler = proc(id, arguments: JsonNode) {.gcsafe, upraises:[].}

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
      handler(id, arguments)

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
  proc handler(id, arguments: JsonNode) =
    if log =? Log.fromJson(arguments["result"]).catch:
      callback(log)
  return await provider.subscribe("logs", filter.some, handler)

method subscribe*(provider: JsonRpcProvider,
                  callback: BlockHandler):
                 Future[Subscription] {.async.} =
  proc handler(id, arguments: JsonNode) =
    if blck =? Block.fromJson(arguments["result"]).catch:
      callback(blck)
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

method wait*(tx: TransactionResponse,
             wantedConfirms = DEFAULT_CONFIRMATIONS,
             timeoutInBlocks = RECEIPT_TIMEOUT_BLKS.some): # will error if tx not mined in x blocks
            Future[TransactionReceipt]
            {.async, upraises: [JsonRpcProviderError].} = # raises for clarity

  var
    receipt: ?TransactionReceipt
    subscription: JsonRpcSubscription

  let
    provider = JsonRpcProvider(tx.provider)
    retFut = newFuture[TransactionReceipt]("wait")

  proc confirmations(receipt: TransactionReceipt, atBlkNum: UInt256): UInt256 =

    var confirms = (atBlkNum - !receipt.blockNumber) + 1
    if confirms <= 0: confirms = 1.u256
    return confirms

  proc newBlock(blk: Block) =
    # has been mined, need to check # of confirmations thus far
    let confirms = (!receipt).confirmations(blk.number)
    if confirms >= wantedConfirms.u256:
      # fire and forget
      discard subscription.unsubscribe()
      retFut.complete(!receipt)

  let startBlock = await provider.getBlockNumber()

  # loop until the tx is mined, or times out (in blocks) if timeout specified
  while receipt.isNone:
    receipt = await provider.getTransactionReceipt(tx.hash)
    if receipt.isSome and (!receipt).blockNumber.isSome:
      break

    if timeoutInBlocks.isSome:
      let currBlock = await provider.getBlockNumber()
      let blocksPassed = (currBlock - startBlock) + 1
      if blocksPassed >= (!timeoutInBlocks).u256:
        raiseProviderError("Transaction was not mined in " &
          $(!timeoutInBlocks) & " blocks")

    await sleepAsync(RECEIPT_POLLING_INTERVAL.seconds)

  # has been mined, need to check # of confirmations thus far
  let confirms = (!receipt).confirmations(startBlock)
  if confirms >= wantedConfirms.u256:
    return !receipt

  else:
    let sub = await provider.subscribe(newBlock)
    subscription = JsonRpcSubscription(sub)
    return (await retFut)

method wait*(tx: Future[TransactionResponse],
             wantedConfirms = DEFAULT_CONFIRMATIONS,
             timeoutInBlocks = RECEIPT_TIMEOUT_BLKS.some):
            Future[TransactionReceipt] {.async.} =
  ## Convenience method that allows wait to be chained to a sendTransaction
  ## call, eg:
  ## `await signer.sendTransaction(populated).wait(3)`

  let txResp = await tx
  return await txResp.wait(wantedConfirms, timeoutInBlocks)

method wait*(tx: Future[?TransactionResponse],
             wantedConfirms = DEFAULT_CONFIRMATIONS,
             timeoutInBlocks = RECEIPT_TIMEOUT_BLKS.some):
            Future[TransactionReceipt] {.async.} =
  ## Convenience method that allows wait to be chained to a contract
  ## transaction, eg:
  ## `await token.connect(signer0)
  ##          .mint(accounts[1], 100.u256)
  ##          .wait(3)`

  let txResp = await tx
  if txResp.isNone:
    raiseProviderError("Transaction hash required. Possibly was a call instead of a send?")

  return await (!txResp).wait(wantedConfirms, timeoutInBlocks)
