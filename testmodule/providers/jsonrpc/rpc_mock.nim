import ../../examples
import ../../../ethers/provider
import ../../../ethers/providers/jsonrpc/conversions

import std/sequtils
import pkg/stew/byteutils
import pkg/json_rpc/rpcserver except `%`, `%*`
import pkg/json_rpc/errors

type MockRpcHttpServer* = ref object
  filters*: seq[string]
  srv: RpcHttpServer

proc new*(_: type MockRpcHttpServer): MockRpcHttpServer =
  let srv = newRpcHttpServer(["127.0.0.1:0"])
  MockRpcHttpServer(filters: @[], srv: srv)

proc invalidateFilter*(server: MockRpcHttpServer, jsonId: JsonNode) =
  server.filters.keepItIf it != jsonId.getStr

proc start*(server: MockRpcHttpServer) =
  server.srv.router.rpc("eth_newFilter") do(filter: EventFilter) -> string:
    let filterId = "0x" & (array[16, byte].example).toHex
    server.filters.add filterId
    return filterId

  server.srv.router.rpc("eth_newBlockFilter") do() -> string:
    let filterId = "0x" & (array[16, byte].example).toHex
    server.filters.add filterId
    return filterId

  server.srv.router.rpc("eth_getFilterChanges") do(id: string) -> seq[string]:
    if id notin server.filters:
      raise (ref ApplicationError)(code: -32000, msg: "filter not found")

    return @[]

  server.srv.router.rpc("eth_uninstallFilter") do(id: string) -> bool:
    if id notin server.filters:
      raise (ref ApplicationError)(code: -32000, msg: "filter not found")

    server.invalidateFilter(%id)
    return true

  server.srv.start()

proc stop*(server: MockRpcHttpServer) {.async.} =
  await server.srv.stop()
  await server.srv.closeWait()

proc localAddress*(server: MockRpcHttpServer): seq[TransportAddress] =
  return server.srv.localAddress()
