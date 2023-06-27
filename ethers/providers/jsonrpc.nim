import std/json
import std/tables
import std/uri
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

push: {.upraises: [].}

type
  JsonRpcProvider* = ref object of Provider
    client: Future[RpcClient]
    subscriptions: Future[JsonRpcSubscriptions]
  JsonRpcSigner* = ref object of Signer
    provider: JsonRpcProvider
    address: ?Address
  JsonRpcProviderError* = object of ProviderError
  SubscriptionHandler = proc(id, arguments: JsonNode): Future[void] {.gcsafe, upraises:[].}

proc raiseProviderError(message: string) {.upraises: [JsonRpcProviderError].} =
  var message = message
  try:
    message = parseJson(message){"message"}.getStr
  except Exception:
    discard
  raise newException(JsonRpcProviderError, message)

template convertError(body) =
  try:
    body
  except JsonRpcError as error:
    raiseProviderError(error.msg)
  # Catch all ValueErrors for now, at least until JsonRpcError is actually
  # raised. PR created: https://github.com/status-im/nim-json-rpc/pull/151
  except ValueError as error:
    raiseProviderError(error.msg)

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
    await initialized
    return client

  proc awaitSubscriptions: Future[JsonRpcSubscriptions] {.async.} =
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

method getTransactionReceipt*(provider: JsonRpcProvider,
                            txHash: TransactionHash):
                           Future[?TransactionReceipt] {.async.} =
  convertError:
    let client = await provider.client
    return await client.eth_getTransactionReceipt(txHash)

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
                  filter: Filter,
                  onLog: LogHandler):
                 Future[Subscription] {.async.} =
  convertError:
    let subscriptions = await provider.subscriptions
    return await subscriptions.subscribeLogs(filter, onLog)

method subscribe*(provider: JsonRpcProvider,
                  onBlock: BlockHandler):
                 Future[Subscription] {.async.} =
  convertError:
    let subscriptions = await provider.subscriptions
    return await subscriptions.subscribeBlocks(onBlock)

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
  convertError:
    let client = await signer.provider.client
    let address = await signer.getAddress()
    return await client.eth_sign(address, message)

method sendTransaction*(signer: JsonRpcSigner,
                        transaction: Transaction): Future[TransactionResponse] {.async.} =
  convertError:
    let
      client = await signer.provider.client
      hash = await client.eth_sendTransaction(transaction)

    return TransactionResponse(hash: hash, provider: signer.provider)
