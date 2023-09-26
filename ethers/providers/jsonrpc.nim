import std/json
import std/tables
import std/uri
import pkg/chronicles
import pkg/eth/common/eth_types_json_serialization
import pkg/json_rpc/rpcclient
import pkg/json_rpc/errors
import ../basics
import ../provider
import ../signer
import ./jsonrpc/rpccalls
import ./jsonrpc/conversions
import ./jsonrpc/subscriptions

export json
export basics
export provider
export chronicles

push: {.upraises: [].}

logScope:
  topics = "ethers jsonrpc"

type
  JsonRpcProvider* = ref object of Provider
    client: Future[RpcClient]
    subscriptions: Future[JsonRpcSubscriptions]
  JsonRpcSigner* = ref object of Signer
    provider: JsonRpcProvider
    address: ?Address
  JsonRpcProviderError* = object of ProviderError
    nonce*: ?UInt256
  JsonRpcSubscription* = ref object of Subscription
    subscriptions: JsonRpcSubscriptions
    id: JsonNode

proc raiseJsonRpcProviderError(message: string) {.upraises: [JsonRpcProviderError].} =
  var message = message
  try:
    message = parseJson(message){"message"}.getStr
  except Exception:
    discard
  let ex = newException(JsonRpcProviderError, message)
  ex[].nonce = nonce
  raise ex

template convertError(nonce = none UInt256, body) =
  try:
    body
  except JsonRpcError as error:
    trace "jsonrpc error", error = error.msg
    raiseProviderError(error.msg, nonce)
  # Catch all ValueErrors for now, at least until JsonRpcError is actually
  # raised. PR created: https://github.com/status-im/nim-json-rpc/pull/151
  except ValueError as error:
    trace "jsonrpc error (from rpc client)", error = error.msg
    raiseProviderError(error.msg, nonce)

template convertError(body) =
  try:
    body
  except JsonRpcError as error:
    raiseJsonRpcProviderError(error.msg)
  # Catch all ValueErrors for now, at least until JsonRpcError is actually
  # raised. PR created: https://github.com/status-im/nim-json-rpc/pull/151
  except ValueError as error:
    raiseJsonRpcProviderError(error.msg)

# Provider

const defaultUrl = "http://localhost:8545"
const defaultPollingInterval = 4.seconds

proc jsonHeaders: seq[(string, string)] =
  @[("Content-Type", "application/json")]

proc new*(_: type JsonRpcProvider,
          url=defaultUrl,
          pollingInterval=defaultPollingInterval): JsonRpcProvider =
  var initialized: Future[void]
  var client: RpcClient
  var subscriptions: JsonRpcSubscriptions

  proc initialize {.async.} =
    case parseUri(url).scheme
    of "ws", "wss":
      let websocket = newRpcWebSocketClient(getHeaders = jsonHeaders)
      await websocket.connect(url)
      client = websocket
      subscriptions = JsonRpcSubscriptions.new(websocket)
    else:
      let http = newRpcHttpClient(getHeaders = jsonHeaders)
      await http.connect(url)
      client = http
      subscriptions = JsonRpcSubscriptions.new(http,
                                               pollingInterval = pollingInterval)

  proc awaitClient: Future[RpcClient] {.async.} =
    convertError:
      await initialized
      return client

  proc awaitSubscriptions: Future[JsonRpcSubscriptions] {.async.} =
    convertError:
      await initialized
      return subscriptions

  initialized = initialize()
  JsonRpcProvider(client: awaitClient(), subscriptions: awaitSubscriptions())

proc send*(provider: JsonRpcProvider,
           call: string,
           arguments: seq[JsonNode] = @[]): Future[JsonNode] {.async.} =
  convertError:
    let client = await provider.client
    return await client.call(call, %arguments)

proc listAccounts*(provider: JsonRpcProvider): Future[seq[Address]] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_accounts()

proc getSigner*(provider: JsonRpcProvider): JsonRpcSigner =
  JsonRpcSigner(provider: provider)

proc getSigner*(provider: JsonRpcProvider, address: Address): JsonRpcSigner =
  JsonRpcSigner(provider: provider, address: some address)

method getBlockNumber*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_blockNumber()

method getBlock*(provider: JsonRpcProvider,
                 tag: BlockTag): Future[?Block] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_getBlockByNumber(tag, false)

method call*(provider: JsonRpcProvider,
             tx: JsonNode,
             blockTag = BlockTag.latest): Future[seq[byte]] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_call(tx, blockTag)

method call*(provider: JsonRpcProvider,
             tx: Transaction,
             blockTag = BlockTag.latest): Future[seq[byte]] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_call(tx, blockTag)

method getGasPrice*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_gasPrice()

method getTransactionCount*(provider: JsonRpcProvider,
                            address: Address,
                            blockTag = BlockTag.latest):
                           Future[UInt256] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_getTransactionCount(address, blockTag)

method getTransaction*(provider: JsonRpcProvider,
                       txHash: TransactionHash):
                      Future[?PastTransaction] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_getTransactionByHash(txHash)

method getTransactionReceipt*(provider: JsonRpcProvider,
                              txHash: TransactionHash):
                             Future[?TransactionReceipt] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_getTransactionReceipt(txHash)

method getLogs*(provider: JsonRpcProvider,
                filter: EventFilter):
               Future[seq[Log]] {.async.} =
  convertError:
    let client = await provider.client
    let logsJson = if filter of Filter:
                    await client.eth_getLogs(Filter(filter))
                   elif filter of FilterByBlockHash:
                    await client.eth_getLogs(FilterByBlockHash(filter))
                   else:
                    await client.eth_getLogs(filter)

    var logs: seq[Log] = @[]
    for logJson in logsJson.getElems:
      if log =? Log.fromJson(logJson).catch:
        logs.add log

    return logs

method estimateGas*(provider: JsonRpcProvider,
                    transaction: Transaction): Future[UInt256] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_estimateGas(transaction)

method getChainId*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  convertError:
    let client = await provider.client
    try:
      return await client.eth_chainId()
    except CatchableError:
      return parse(await client.net_version(), UInt256)

method sendTransaction*(provider: JsonRpcProvider, rawTransaction: seq[byte]): Future[TransactionResponse] {.async.} =
  convertError:
    let
      client = await provider.client
      hash = await client.eth_sendRawTransaction(rawTransaction)

    return TransactionResponse(hash: hash, provider: provider)

method subscribe*(provider: JsonRpcProvider,
                  filter: EventFilter,
                  onLog: LogHandler):
                 Future[Subscription] {.async.} =
  convertError:
    let subscriptions = await provider.subscriptions
    let id = await subscriptions.subscribeLogs(filter, onLog)
    return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method subscribe*(provider: JsonRpcProvider,
                  onBlock: BlockHandler):
                 Future[Subscription] {.async.} =
  convertError:
    let subscriptions = await provider.subscriptions
    let id = await subscriptions.subscribeBlocks(onBlock)
    return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method unsubscribe(subscription: JsonRpcSubscription) {.async.} =
  convertError:
    let subscriptions = subscription.subscriptions
    let id = subscription.id
    await subscriptions.unsubscribe(id)

method close*(provider: JsonRpcProvider) {.async.} =
  convertError:
    let client = await provider.client
    let subscriptions = await provider.subscriptions
    await subscriptions.close()
    await client.close()

# Signer

method provider*(signer: JsonRpcSigner): Provider =
  signer.provider

method getAddress*(signer: JsonRpcSigner): Future[Address] {.async.} =
  if address =? signer.address:
    return address

  let accounts = await signer.provider.listAccounts()
  if accounts.len > 0:
    return accounts[0]

  raiseJsonRpcProviderError "no address found"

method signMessage*(signer: JsonRpcSigner,
                    message: seq[byte]): Future[seq[byte]] {.async.} =
  convertError:
    let client = await signer.provider.client
    let address = await signer.getAddress()
    return await client.eth_sign(address, message)

method sendTransaction*(signer: JsonRpcSigner,
                        transaction: Transaction): Future[TransactionResponse] {.async.} =
  convertError:
    if nonce =? transaction.nonce:
      signer.updateNonce(nonce)
    let
      client = await signer.provider.client
      hash = await client.eth_sendTransaction(transaction)

    trace "jsonrpc sendTransaction RESPONSE", nonce = transaction.nonce, hash = hash.to0xHex
    return TransactionResponse(hash: hash, provider: signer.provider)
