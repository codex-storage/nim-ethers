import std/uri
import pkg/json_rpc/rpcclient
import ../basics
import ../provider
import ../signer
import ./rpccalls

export basics
export provider

push: {.upraises: [].}

type
  JsonRpcProvider* = ref object of Provider
    client: Future[RpcClient]
  JsonRpcSigner* = ref object of Signer
    provider: JsonRpcProvider
    address: ?Address
  JsonRpcProviderError* = object of IOError

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

proc getSigner*(provider: JsonRpcProvider): JsonRpcSigner =
  JsonRpcSigner(provider: provider)

proc getSigner*(provider: JsonRpcProvider, address: Address): JsonRpcSigner =
  JsonRpcSigner(provider: provider, address: some address)

method getBlockNumber*(provider: JsonRpcProvider): Future[UInt256] {.async.} =
  let client = await provider.client
  return await client.eth_blockNumber()

method call*(provider: JsonRpcProvider,
             tx: Transaction): Future[seq[byte]] {.async.} =
  let client = await provider.client
  return await client.eth_call(tx)

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
