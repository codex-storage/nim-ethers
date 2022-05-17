import chronos
import pkg/ethers/providers/jsonrpc


proc mineBlocks*(provider: JsonRpcProvider, blks: int) {.async.} =
  for i in 1..blks:
    discard await provider.send("evm_mine")
    await sleepAsync(1.seconds)
