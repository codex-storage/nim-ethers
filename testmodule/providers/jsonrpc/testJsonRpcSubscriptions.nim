import std/os
import std/importutils
import pkg/asynctest
import pkg/serde
import pkg/json_rpc/rpcclient
import pkg/json_rpc/rpcserver
import ethers/provider
import ethers/providers/jsonrpc/subscriptions

import ../../examples
import ./rpc_mock

suite "JsonRpcSubscriptions":

  test "can be instantiated with an http client":
    let client = newRpcHttpClient()
    let subscriptions = JsonRpcSubscriptions.new(client)
    check not isNil subscriptions

  test "can be instantiated with a websocket client":
    let client = newRpcWebSocketClient()
    let subscriptions = JsonRpcSubscriptions.new(client)
    check not isNil subscriptions

template subscriptionTests(subscriptions, client) =

  test "subscribes to new blocks":
    var latestBlock: Block
    proc callback(blck: ?!Block) =
      latestBlock = blck.value
    let subscription = await subscriptions.subscribeBlocks(callback)
    discard await client.call("evm_mine", newJArray())
    check eventually latestBlock.number.isSome
    check latestBlock.hash.isSome
    check latestBlock.timestamp > 0.u256
    await subscriptions.unsubscribe(subscription)

  test "stops listening to new blocks when unsubscribed":
    var count = 0
    proc callback(blck: ?!Block) =
      if blck.isOk:
        inc count
    let subscription = await subscriptions.subscribeBlocks(callback)
    discard await client.call("evm_mine", newJArray())
    check eventually count > 0
    await subscriptions.unsubscribe(subscription)
    count = 0
    discard await client.call("evm_mine", newJArray())
    await sleepAsync(100.millis)
    check count == 0

  test "unsubscribing from a non-existent subscription does not do any harm":
    await subscriptions.unsubscribe(newJInt(0))

  test "duplicate unsubscribe is harmless":
    proc callback(blck: ?!Block) = discard
    let subscription = await subscriptions.subscribeBlocks(callback)
    await subscriptions.unsubscribe(subscription)
    await subscriptions.unsubscribe(subscription)

  test "stops listening to new blocks when provider is closed":
    var count = 0
    proc callback(blck: ?!Block) =
      if blck.isOk:
        inc count
    discard await subscriptions.subscribeBlocks(callback)
    discard await client.call("evm_mine", newJArray())
    check eventually count > 0
    await subscriptions.close()
    count = 0
    discard await client.call("evm_mine", newJArray())
    await sleepAsync(100.millis)
    check count == 0

suite "Web socket subscriptions":

  var subscriptions: JsonRpcSubscriptions
  var client: RpcWebSocketClient

  setup:
    client = newRpcWebSocketClient()
    await client.connect("ws://"  & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545"))
    subscriptions = JsonRpcSubscriptions.new(client)
    subscriptions.start()

  teardown:
    await subscriptions.close()
    await client.close()

  subscriptionTests(subscriptions, client)

suite "HTTP polling subscriptions":

  var subscriptions: JsonRpcSubscriptions
  var client: RpcHttpClient

  setup:
    client = newRpcHttpClient()
    await client.connect("http://" & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545"))
    subscriptions = JsonRpcSubscriptions.new(client,
                                             pollingInterval = 100.millis)
    subscriptions.start()

  teardown:
    await subscriptions.close()
    await client.close()

  subscriptionTests(subscriptions, client)

suite "HTTP polling subscriptions - mock tests":

  var subscriptions: PollingSubscriptions
  var client: RpcHttpClient
  var mockServer: MockRpcHttpServer

  privateAccess(PollingSubscriptions)
  privateAccess(JsonRpcSubscriptions)

  proc startServer() {.async.} =
    mockServer = MockRpcHttpServer.new()
    mockServer.start()
    await client.connect("http://" & $mockServer.localAddress()[0])

  proc stopServer() {.async.} =
    await mockServer.stop()

  setup:
    client = newRpcHttpClient()
    await startServer()

    subscriptions = PollingSubscriptions(
                      JsonRpcSubscriptions.new(
                        client,
                        pollingInterval = 1.millis))
    subscriptions.start()

  teardown:
    await subscriptions.close()
    await client.close()
    await mockServer.stop()

  test "filter not found error recreates log filter":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard

    check subscriptions.logFilters.len == 0
    check subscriptions.subscriptionMapping.len == 0

    let id = await subscriptions.subscribeLogs(filter, emptyHandler)

    check subscriptions.logFilters[id] == filter
    check subscriptions.subscriptionMapping[id] == id
    check subscriptions.logFilters.len == 1
    check subscriptions.subscriptionMapping.len == 1

    mockServer.invalidateFilter(id)

    check eventually subscriptions.subscriptionMapping[id] != id

  test "recreated log filter can be still unsubscribed using the original id":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard
    let id = await subscriptions.subscribeLogs(filter, emptyHandler)
    mockServer.invalidateFilter(id)
    check eventually subscriptions.subscriptionMapping[id] != id

    await subscriptions.unsubscribe(id)

    check not subscriptions.logFilters.hasKey id
    check not subscriptions.subscriptionMapping.hasKey id

  test "filter not found error recreates block filter":
    let emptyHandler = proc(blck: ?!Block) = discard

    check subscriptions.subscriptionMapping.len == 0
    let id = await subscriptions.subscribeBlocks(emptyHandler)
    check subscriptions.subscriptionMapping[id] == id

    mockServer.invalidateFilter(id)

    check eventually subscriptions.subscriptionMapping[id] != id

  test "recreated block filter can be still unsubscribed using the original id":
    let emptyHandler = proc(blck: ?!Block) = discard
    let id = await subscriptions.subscribeBlocks(emptyHandler)
    mockServer.invalidateFilter(id)
    check eventually subscriptions.subscriptionMapping[id] != id

    await subscriptions.unsubscribe(id)

    check not subscriptions.subscriptionMapping.hasKey id

  test "polling continues with new filter after temporary error":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard

    let id = await subscriptions.subscribeLogs(filter, emptyHandler)

    await stopServer()
    mockServer.invalidateFilter(id)
    await sleepAsync(50.milliseconds)
    await startServer()

    check eventually subscriptions.subscriptionMapping[id] != id

  test "calls callback with failed result on error":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    var failedResultReceived = false

    proc handler(log: ?!Log) =
      if log.isErr:
        failedResultReceived = true

    let id = await subscriptions.subscribeLogs(filter, handler)

    await sleepAsync(50.milliseconds)
    mockServer.nextGetChangesReturnsError = true
    check eventually failedResultReceived
