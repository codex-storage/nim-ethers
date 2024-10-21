import ../../examples
import ../../../ethers/provider
import ../../../ethers/providers/jsonrpc/conversions

import std/tables
import pkg/stew/byteutils
import pkg/json_rpc/rpcserver except `%`, `%*`
import pkg/json_rpc/errors


type MockRpcHttpServer* = ref object
  filters*: Table[string, bool]
  newFilterCounter*: int
  srv: RpcHttpServer

proc new*(_: type MockRpcHttpServer): MockRpcHttpServer =
  MockRpcHttpServer(filters: initTable[string, bool](), newFilterCounter: 0, srv: newRpcHttpServer(["127.0.0.1:0"]))

proc invalidateFilter*(server: MockRpcHttpServer, id: string) =
  server.filters[id] = false

proc start*(server: MockRpcHttpServer) =
  server.srv.router.rpc("eth_newFilter") do(filter: EventFilter) -> string:
    let filterId = "0x" & (array[16, byte].example).toHex
    server.filters[filterId] = true
    server.newFilterCounter += 1
    return filterId

  server.srv.router.rpc("eth_getFilterChanges") do(id: string) -> seq[string]:
    if(not hasKey(server.filters, id) or not server.filters[id]):
      raise (ref ApplicationError)(code: -32000, msg: "filter not found")

    return @[]

  server.srv.router.rpc("eth_uninstallFilter") do(id: string) -> bool:
    if(not hasKey(server.filters, id)):
      raise (ref ApplicationError)(code: -32000, msg: "filter not found")

    del(server.filters, id)
    return true

  server.srv.start()

proc stop*(server: MockRpcHttpServer) {.async.} =
  await server.srv.stop()
  await server.srv.closeWait()


proc localAddress*(server: MockRpcHttpServer): seq[TransportAddress] =
  return server.srv.localAddress()
