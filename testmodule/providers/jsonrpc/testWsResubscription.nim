import std/os
import std/importutils
import pkg/asynctest
import pkg/json_rpc/rpcclient
import ethers/provider
import ethers/providers/jsonrpc/subscriptions

import ../../examples
import ./rpc_mock

suite "Websocket re-subscriptions":
  privateAccess(JsonRpcSubscriptions)

  var subscriptions: JsonRpcSubscriptions
  var client: RpcWebSocketClient
  var resubscribeInterval: int

  setup:
    resubscribeInterval = 3
    client = newRpcWebSocketClient()
    await client.connect("ws://"  & getEnv("ETHERS_TEST_PROVIDER", "localhost:8545"))
    subscriptions = JsonRpcSubscriptions.new(client, resubscribeInterval = resubscribeInterval)
    subscriptions.start()

  teardown:
    await subscriptions.close()
    await client.close()

  test "unsubscribing from a log filter while subscriptions are being resubscribed does not cause a concurrency error":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard

    for i in 1..10:
      discard await subscriptions.subscribeLogs(filter, emptyHandler)

    # Wait until the re-subscription starts
    await sleepAsync(resubscribeInterval.seconds)

    # Attempt to modify callbacks while its being iterated
    discard await subscriptions.subscribeLogs(filter, emptyHandler)

  test "resubscribe events take effect with new subscription IDs in the log filters":
    let filter = EventFilter(address: Address.example, topics: @[array[32, byte].example])
    let emptyHandler = proc(log: ?!Log) = discard
    let id = await subscriptions.subscribeLogs(filter, emptyHandler)

    check id in subscriptions.logFilters
    check subscriptions.logFilters.len == 1

    # Make sure the subscription is done
    await sleepAsync((resubscribeInterval + 1).seconds)

    # The previous subscription should not be in the log filters
    check id notin subscriptions.logFilters

    # There is still one subscription which is the new one
    check subscriptions.logFilters.len == 1
