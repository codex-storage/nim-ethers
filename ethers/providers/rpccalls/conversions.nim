import std/json
import pkg/stew/byteutils
import ../../basics
import ../../transaction
import ../../blocktag

# byte sequence

func `%`*(bytes: seq[byte]): JsonNode =
  %("0x" & bytes.toHex)

func fromJson*(json: JsonNode, name: string, result: var seq[byte]) =
  result = hexToSeqByte(json.getStr())

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

# Transaction

func `%`*(tx: Transaction): JsonNode =
  result = %{ "to": %tx.to, "data": %tx.data }
  if sender =? tx.sender:
    result["from"] = %sender

# BlockTag

func `%`*(blockTag: BlockTag): JsonNode =
  %($blockTag)
