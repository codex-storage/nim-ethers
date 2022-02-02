import std/os
import pkg/json_rpc/rpcclient
import ../basics
import ../transaction
import ../blocktag
import ../provider
import ./conversions

const file = currentSourcePath.parentDir / "rpccalls" / "signatures.nim"

createRpcSigs(RpcClient, file)
