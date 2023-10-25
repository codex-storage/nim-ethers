import pkg/stew/byteutils
import ./basics

type
  TransactionType* = enum
    Legacy = 0,
    AccessList = 1,
    Dynamic = 2
  Transaction* = object
    sender*: ?Address
    to*: Address
    data*: seq[byte]
    value*: UInt256
    nonce*: ?UInt256
    chainId*: ?UInt256
    gasPrice*: ?UInt256
    maxFee*: ?UInt256
    maxPriorityFee*: ?UInt256
    gasLimit*: ?UInt256
    transactionType*: ?TransactionType

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
  if txType =? transaction.transactionType:
    result &= ", type: " & $txType
  result &= ")"
