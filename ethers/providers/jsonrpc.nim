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
import ./jsonrpc/json

export json
export basics
export provider
export chronicles

{.push raises: [].}

logScope:
  topics = "ethers jsonrpc"

type
  JsonRpcProvider* = ref object of Provider
    client: Future[RpcClient]
    subscriptions: Future[JsonRpcSubscriptions]

  JsonRpcProviderError* = object of ProviderError
  JsonRpcSubscription* = ref object of Subscription
    subscriptions: JsonRpcSubscriptions
    id: JsonNode

  # Signer
  JsonRpcSigner* = ref object of Signer
    provider: JsonRpcProvider
    address: ?Address
  JsonRpcSignerError* = object of SignerError

proc raiseJsonRpcProviderError(
  message: string) {.raises: [JsonRpcProviderError].} =

  var message = message
  if json =? JsonNode.fromJson(message):
    if "message" in json:
      message = json{"message"}.getStr
  raise newException(JsonRpcProviderError, message)

template convertError(body) =
  try:
    body
  except JsonRpcError as error:
    raiseJsonRpcProviderError(error.msg)
  except CatchableError as error:
    raiseJsonRpcProviderError(error.msg)

# Provider

const defaultUrl = "http://localhost:8545"
const defaultPollingInterval = 4.seconds

proc jsonHeaders: seq[(string, string)] =
  @[("Content-Type", "application/json")]

proc new*(
  _: type JsonRpcProvider,
  url=defaultUrl,
  pollingInterval=defaultPollingInterval): JsonRpcProvider {.raises: [JsonRpcProviderError].} =

  var initialized: Future[void]
  var client: RpcClient
  var subscriptions: JsonRpcSubscriptions

  proc initialize {.async: (raises:[JsonRpcProviderError]).} =
    convertError:
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
      subscriptions.init()

  proc awaitClient: Future[RpcClient] {.async:(raises:[JsonRpcProviderError]).} =
    convertError:
      await initialized
      return client

  proc awaitSubscriptions: Future[JsonRpcSubscriptions] {.async:(raises:[JsonRpcProviderError]).} =
    convertError:
      await initialized
      return subscriptions

  initialized = initialize()
  return JsonRpcProvider(client: awaitClient(), subscriptions: awaitSubscriptions())

proc callImpl(
  client: RpcClient,
  call: string,
  args: JsonNode): Future[JsonNode] {.async: (raises: [JsonRpcProviderError]).} =

  without response =? (await client.call(call, %args)).catch, error:
    raiseJsonRpcProviderError error.msg
  without json =? JsonNode.fromJson(response.string), error:
    raiseJsonRpcProviderError "Failed to parse response: " & error.msg
  json

proc send*(
  provider: JsonRpcProvider,
  call: string,
  arguments: seq[JsonNode] = @[]): Future[JsonNode]
  {.async: (raises: [JsonRpcProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.callImpl(call, %arguments)

proc listAccounts*(provider: JsonRpcProvider): Future[seq[Address]]
  {.async: (raises: [JsonRpcProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_accounts()

proc getSigner*(provider: JsonRpcProvider): JsonRpcSigner =
  JsonRpcSigner(provider: provider)

proc getSigner*(provider: JsonRpcProvider, address: Address): JsonRpcSigner =
  JsonRpcSigner(provider: provider, address: some address)

method getBlockNumber*(
  provider: JsonRpcProvider): Future[UInt256] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_blockNumber()

method getBlock*(
  provider: JsonRpcProvider,
  tag: BlockTag): Future[?Block] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_getBlockByNumber(tag, false)

method call*(
  provider: JsonRpcProvider,
  tx: Transaction,
  blockTag = BlockTag.latest): Future[seq[byte]] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_call(tx, blockTag)

method getGasPrice*(
  provider: JsonRpcProvider): Future[UInt256] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_gasPrice()

method getTransactionCount*(
  provider: JsonRpcProvider,
  address: Address,
  blockTag = BlockTag.latest): Future[UInt256] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_getTransactionCount(address, blockTag)

method getTransaction*(
  provider: JsonRpcProvider,
  txHash: TransactionHash): Future[?PastTransaction] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_getTransactionByHash(txHash)

method getTransactionReceipt*(
  provider: JsonRpcProvider,
  txHash: TransactionHash): Future[?TransactionReceipt] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_getTransactionReceipt(txHash)

method getLogs*(
  provider: JsonRpcProvider,
  filter: EventFilter): Future[seq[Log]] {.async: (raises:[ProviderError]).} =

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
      if log =? Log.fromJson(logJson):
        logs.add log

    return logs

method estimateGas*(
  provider: JsonRpcProvider,
  transaction: Transaction,
  blockTag = BlockTag.latest): Future[UInt256] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    return await client.eth_estimateGas(transaction, blockTag)

method getChainId*(
  provider: JsonRpcProvider): Future[UInt256] {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    try:
      return await client.eth_chainId()
    except CatchableError:
      return parse(await client.net_version(), UInt256)

method sendTransaction*(
  provider: JsonRpcProvider,
  rawTransaction: seq[byte]): Future[TransactionResponse]
  {.async: (raises:[ProviderError]).} =

  convertError:
    let
      client = await provider.client
      hash = await client.eth_sendRawTransaction(rawTransaction)

    return TransactionResponse(hash: hash, provider: provider)

method subscribe*(
  provider: JsonRpcProvider,
  filter: EventFilter,
  onLog: LogHandler): Future[Subscription] {.async: (raises:[ProviderError]).} =

  convertError:
    let subscriptions = await provider.subscriptions
    let id = await subscriptions.subscribeLogs(filter, onLog)
    return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method subscribe*(
  provider: JsonRpcProvider,
  onBlock: BlockHandler): Future[Subscription] {.async: (raises:[ProviderError]).} =

  convertError:
    let subscriptions = await provider.subscriptions
    let id = await subscriptions.subscribeBlocks(onBlock)
    return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method unsubscribe*(
  subscription: JsonRpcSubscription) {.async: (raises:[ProviderError]).} =

  convertError:
    let subscriptions = subscription.subscriptions
    let id = subscription.id
    await subscriptions.unsubscribe(id)

method close*(
  provider: JsonRpcProvider) {.async: (raises:[ProviderError]).} =

  convertError:
    let client = await provider.client
    let subscriptions = await provider.subscriptions
    await subscriptions.close()
    await client.close()

# Signer

proc raiseJsonRpcSignerError(
  message: string) {.raises: [JsonRpcSignerError].} =

  var message = message
  if json =? JsonNode.fromJson(message):
    if "message" in json:
      message = json{"message"}.getStr
  raise newException(JsonRpcSignerError, message)

template convertSignerError(body) =
  try:
    body
  except JsonRpcError as error:
    raiseJsonRpcSignerError(error.msg)
  except CatchableError as error:
    raise newException(JsonRpcSignerError, error.msg)

method provider*(signer: JsonRpcSigner): Provider {.gcsafe, raises: [SignerError].} =
  signer.provider

method getAddress*(
  signer: JsonRpcSigner): Future[Address] {.async: (raises:[SignerError]).} =

  if address =? signer.address:
    return address

  convertSignerError:
    let accounts = await signer.provider.listAccounts()
    if accounts.len > 0:
      return accounts[0]

  raiseJsonRpcSignerError "no address found"

method signMessage*(
  signer: JsonRpcSigner,
  message: seq[byte]): Future[seq[byte]] {.async: (raises:[SignerError]).} =

  convertSignerError:
    let client = await signer.provider.client
    let address = await signer.getAddress()
    return await client.eth_sign(address, message)

method sendTransaction*(
  signer: JsonRpcSigner,
  transaction: Transaction): Future[TransactionResponse]
  {.async: (raises:[SignerError]).} =

  convertSignerError:
    if nonce =? transaction.nonce:
      signer.updateNonce(nonce)
    let
      client = await signer.provider.client
      hash = await client.eth_sendTransaction(transaction)

    return TransactionResponse(hash: hash, provider: signer.provider)
