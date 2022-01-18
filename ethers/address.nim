import pkg/stew/byteutils
import pkg/questionable
import pkg/upraises

push: {.upraises: [].}

type
  Address* = distinct array[20, byte]

func init*(_: type Address, bytes: array[20, byte]): Address =
  Address(bytes)

func init*(_: type Address, hex: string): ?Address =
  try:
    let bytes = array[20, byte].fromHex(hex)
    some Address.init(bytes)
  except ValueError:
    none Address

func toArray(address: Address): array[20, byte] =
  array[20, byte](address)

func `$`*(address: Address): string =
  "0x" & toHex(address.toArray)

func `==`*(a, b: Address): bool {.borrow.}
