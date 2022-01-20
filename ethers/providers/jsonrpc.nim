import std/uri
import pkg/json_rpc/rpcclient
import ../basics
import ../provider
import ./rpccalls

export basics
export provider

push: {.upraises: [].}

type JsonRpcProvider* = ref object of Provider
  client: Future[RpcClient]

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

proc new*(_: type JsonRpcProvider, url=defaultUrl): JsonRpcProvider =
  JsonRpcProvider(client: RpcClient.connect(url))

proc send*(provider: JsonRpcProvider,
           call: string,
           arguments = %(@[])): Future[JsonNode] {.async.} =
  let client = await provider.client
  return await client.call(call, arguments)

proc listAccounts*(provider: JsonRpcProvider): Future[seq[Address]] {.async.} =
  let client = await provider.client
  return await client.eth_accounts()

method getBlockNumber*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  let client = await provider.client
  return await client.eth_blockNumber()

method call*(provider: JsonRpcProvider,
             tx: Transaction): Future[seq[byte]] {.async.} =
  let client = await provider.client
  return await client.eth_call(tx)
