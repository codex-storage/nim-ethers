import std/json
import std/os
import std/sequtils
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
    proc callback(blck: Block) =
      latestBlock = blck
    let subscription = await subscriptions.subscribeBlocks(callback)
    discard await client.call("evm_mine", newJArray())
    check eventually latestBlock.number.isSome
    check latestBlock.hash.isSome
    check latestBlock.timestamp > 0.u256
    await subscriptions.unsubscribe(subscription)

  test "stops listening to new blocks when unsubscribed":
    var count = 0
    proc callback(blck: Block) =
      inc count
    let subscription = await subscriptions.subscribeBlocks(callback)
    discard await client.call("evm_mine", newJArray())
    check eventually count > 0
    await subscriptions.unsubscribe(subscription)
    count = 0
    discard await client.call("evm_mine", newJArray())
    await sleepAsync(100.millis)
    check count == 0

  test "stops listening to new blocks when provider is closed":
    var count = 0
    proc callback(blck: Block) =
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

suite "HTTP polling subscriptions - filter not found":

  var subscriptions: JsonRpcSubscriptions
  var client: RpcHttpClient
  var mockServer: MockRpcHttpServer

  setup:
    mockServer = MockRpcHttpServer.new()
    mockServer.start()

    client = newRpcHttpClient()
    await client.connect("http://" & $mockServer.localAddress()[0])

    subscriptions = JsonRpcSubscriptions.new(client,
                                             pollingInterval = 100.millis)
    subscriptions.start()

  teardown:
    await subscriptions.close()
    await client.close()
    await mockServer.stop()

  test "filter not found error recreates filter":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: Log) = discard

    check mockServer.newFilterCounter == 0
    let jsonId = await subscriptions.subscribeLogs(filter, emptyHandler)
    let id = string.fromJson(jsonId).tryGet
    check mockServer.newFilterCounter == 1

    await sleepAsync(300.millis)
    mockServer.invalidateFilter(id)
    await sleepAsync(300.millis)
    check mockServer.newFilterCounter == 2

  test "recreated filter can be still unsubscribed using the original id":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: Log) = discard

    check mockServer.newFilterCounter == 0
    let jsonId = await subscriptions.subscribeLogs(filter, emptyHandler)
    let id = string.fromJson(jsonId).tryGet
    check mockServer.newFilterCounter == 1

    await sleepAsync(300.millis)
    mockServer.invalidateFilter(id)
    check eventually mockServer.newFilterCounter == 2
    check mockServer.filters[id] == false
    check mockServer.filters.len() == 2
    await subscriptions.unsubscribe(jsonId)
    check mockServer.filters.len() == 1

    # invalidateFilter sets the filter's value to false which will return the "filter not found"
    # unsubscribing will actually delete the key from filters table
    # hence after unsubscribing the only key left in the table should be the original id
    for key in mockServer.filters.keys():
      check key == id
