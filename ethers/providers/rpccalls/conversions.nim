import std/json
import ../../basics

# Address

func `%`*(address: Address): JsonNode =
  %($address)

func fromJson*(json: JsonNode, name: string, result: var Address) =
  if address =? Address.init(json.getStr()):
    result = address
  else:
    raise newException(ValueError, "\""  & name & "\"is not an Address")

# UInt256

func `%`*(integer: UInt256): JsonNode =
  %toHex(integer)

func fromJson*(json: JsonNode, name: string, result: var UInt256) =
  result = UInt256.fromHex(json.getStr())
