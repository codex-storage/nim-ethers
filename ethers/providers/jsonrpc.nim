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
  let client = await provider.client
  discard await client.eth_unsubscribe(subscription.id)
  provider.subscriptions.del(subscription.id)

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
                        transaction: Transaction) {.async.} =
  let client = await signer.provider.client
  discard await client.eth_sendTransaction(transaction)
