import pkg/stew/byteutils
import ./basics
import ./providers/jsonrpc/json

type
  TransactionType* = enum
    Legacy = 0,
    AccessList = 1,
    Dynamic = 2
  Transaction* = object
    sender* {.serialize.}: ?Address
    to* {.serialize.}: Address
    data* {.serialize.}: seq[byte]
    value* {.serialize.}: UInt256
    nonce* {.serialize.}: ?UInt256
    chainId* {.serialize.}: ?UInt256
    gasPrice* {.serialize.}: ?UInt256
    maxFee* {.serialize.}: ?UInt256
    maxPriorityFee* {.serialize.}: ?UInt256
    gasLimit* {.serialize.}: ?UInt256
    `type`* {.serialize.}: ?TransactionType

func `$`*(transaction: Transaction): string =
  result = "("
  if sender =? transaction.sender:
    result &= "from: " & $sender & ", "
  result &= "to: " & $transaction.to & ", "
  result &= "value: " & $transaction.value & ", "
  result &= "data: 0x" & $(transaction.data.toHex)
  if nonce =? transaction.nonce:
    result &= ", nonce: " & $nonce
  if chainId =? transaction.chainId:
    result &= ", chainId: " & $chainId
  if gasPrice =? transaction.gasPrice:
    result &= ", gasPrice: " & $gasPrice
  if gasLimit =? transaction.gasLimit:
    result &= ", gasLimit: " & $gasLimit
  if txType =? transaction.`type`:
    result &= ", type: " & $txType
  result &= ")"
