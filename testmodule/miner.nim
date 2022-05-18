import chronos
import pkg/ethers/providers/jsonrpc


proc mineBlocks*(provider: JsonRpcProvider, blks: int) {.async.} =
  for i in 1..blks:
    discard await provider.send("evm_mine")
    # Gives time for the subscription to occur in `.wait`.
    # Likely needed in slower environments, like CI.
    await sleepAsync(2.milliseconds)
