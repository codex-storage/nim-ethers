import std/os
import std/importutils
import pkg/asynctest
import pkg/json_rpc/rpcclient
import ethers/provider
import ethers/providers/jsonrpc/subscriptions

import ../../examples
import ./rpc_mock

suite "Web socket re-subscriptions":
  privateAccess(JsonRpcSubscriptions)

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

  test "unsubscribing from a log filter while subscriptions are being resubscribed does not cause a concurrency error.":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard

    let subscription = await subscriptions.subscribeLogs(filter, emptyHandler)

    await sleepAsync(3000.int64.milliseconds)

    try:
        await subscriptions.unsubscribe(subscription)
    except CatchableError:
        fail()

  test "resubscribe events take effect with new subscription IDs in the log filters":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard
    let id = await subscriptions.subscribeLogs(filter, emptyHandler)

    check id in subscriptions.logFilters
    check subscriptions.logFilters.len == 1

    await sleepAsync(4.int64.seconds)

    # The previous subscription should not be in the log filters
    check not (id in subscriptions.logFilters)

    # There is still one subscription which is the new one
    check subscriptions.logFilters.len == 1
