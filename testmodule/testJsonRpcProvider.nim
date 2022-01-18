import pkg/asynctest
import pkg/chronos
import pkg/ethers/providers/jsonrpc

suite "JsonRpcProvider":

  var provider: JsonRpcProvider

  setup:
    provider = JsonRpcProvider.new("ws://localhost:8545")

  test "can be instantiated with a default URL":
    discard JsonRpcProvider.new()

  test "can be instantiated with an HTTP URL":
    discard JsonRpcProvider.new("http://localhost:8545")

  test "can be instantiated with a websocket URL":
    discard JsonRpcProvider.new("ws://localhost:8545")

  test "lists all accounts":
    let accounts = await provider.listAccounts()
    check accounts.len > 0
