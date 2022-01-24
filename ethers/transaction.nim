import pkg/stew/byteutils
import ./basics

type Transaction* = object
  sender*: ?Address
  to*: Address
  data*: seq[byte]

func `$`*(transaction: Transaction): string =
  result = "("
  if sender =? transaction.sender:
    result &= "from: " & $sender & ", "
  result &= "to: " & $transaction.to & ", "
  result &= "data: 0x" & $transaction.data.toHex
  result &= ")"
