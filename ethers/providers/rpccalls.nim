import std/os
import pkg/json_rpc/rpcclient
import ../basics

const file = currentSourcePath.parentDir / "rpccalls" / "signatures.nim"

createRpcSigs(RpcClient, file)
