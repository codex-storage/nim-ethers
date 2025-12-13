import std/os
import pkg/asynctest/chronos/unittest
import pkg/json_rpc/rpcclient
import pkg/json_rpc/rpcserver
import ethers/providers/jsonrpc

let providerUrl = getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")
for url in ["ws://" & providerUrl, "http://"  & providerUrl]:

  suite "JSON-RPC Subscriptions (" & url & ")":

    var provider: JsonRpcProvider

    setup:
      provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)

    teardown:
      await provider.close()

    test "subscribes to new blocks":
      var latestBlock: Block
      proc callback(blck: Block) =
        latestBlock = blck
      let subscription = await provider.subscribe(callback)
      discard await provider.send("evm_mine")
      check eventually latestBlock.number.isSome
      check latestBlock.hash.isSome
      check latestBlock.timestamp > 0.u256
      await subscription.unsubscribe()

    test "stops listening to new blocks when unsubscribed":
      var count = 0
      proc callback(blck: Block) =
        inc count
      let subscription = await provider.subscribe(callback)
      discard await provider.send("evm_mine")
      check eventually count > 0
      await subscription.unsubscribe()
      count = 0
      discard await provider.send("evm_mine")
      await sleepAsync(200.millis)
      check count == 0

    test "duplicate unsubscribe is harmless":
      proc callback(blck: Block) = discard
      let subscription = await provider.subscribe(callback)
      await subscription.unsubscribe()
      await subscription.unsubscribe()

    test "stops listening to new blocks when provider is closed":
      var count = 0
      proc callback(blck: Block) =
        inc count
      discard await provider.subscribe(callback)
      discard await provider.send("evm_mine")
      check eventually count > 0
      await provider.close()
      count = 0
      provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)
      discard await provider.send("evm_mine")
      await sleepAsync(200.millis)
      check count == 0

