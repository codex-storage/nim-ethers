import std/json
import ../../basics

func `%`*(address: Address): JsonNode =
  %($address)

func fromJson*(json: JsonNode, argname: string, result: var Address) =
  if address =? Address.init(json.getStr()):
    result = address
  else:
    raise newException(ValueError, "\""  & argname & "\"is not an Address")
