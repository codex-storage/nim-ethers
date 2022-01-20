import pkg/stew/byteutils
import ./basics

type Transaction* = object
  to*: Address
  data*: seq[byte]

func `$`*(transaction: Transaction): string =
  "(to: " & $transaction.to & ", data: 0x" & $transaction.data.toHex & ")"
