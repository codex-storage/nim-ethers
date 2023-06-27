import std/json
import pkg/asynctest
import pkg/json_rpc/rpcclient
import ethers/provider
import ethers/providers/jsonrpc/subscriptions

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
    proc callback(blck: Block) {.async.} =
      latestBlock = blck
    let subscription = await subscriptions.subscribeBlocks(callback)
    discard await client.call("evm_mine", newJArray())
    check eventually(latestBlock.number.isSome)
    check latestBlock.hash.isSome
    check latestBlock.timestamp > 0.u256
    await subscription.unsubscribe()

suite "Web socket subscriptions":

  var subscriptions: JsonRpcSubscriptions
  var client: RpcWebSocketClient

  setup:
    client = newRpcWebSocketClient()
    await client.connect("ws://localhost:8545")
    subscriptions = JsonRpcSubscriptions.new(client)

  subscriptionTests(subscriptions, client)

suite "HTTP polling subscriptions":

  var subscriptions: JsonRpcSubscriptions
  var client: RpcHttpClient

  setup:
    client = newRpcHttpClient()
    await client.connect("http://localhost:8545")
    subscriptions = JsonRpcSubscriptions.new(client)

  subscriptionTests(subscriptions, client)
