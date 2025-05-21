import ../basics
import ../blocktag

type
  TransactionOverrides* = ref object of RootObj
    nonce*: ?UInt256
    chainId*: ?UInt256
    gasPrice*: ?UInt256
    maxFeePerGas*: ?UInt256
    maxPriorityFeePerGas*: ?UInt256
    gasLimit*: ?UInt256
  CallOverrides* = ref object of TransactionOverrides
    blockTag*: ?BlockTag
