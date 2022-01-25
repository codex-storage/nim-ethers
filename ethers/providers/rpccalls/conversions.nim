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
  %("0x" & toHex(integer))

func fromJson*(json: JsonNode, name: string, result: var UInt256) =
  result = UInt256.fromHex(json.getStr())

# Transaction

func `%`*(transaction: Transaction): JsonNode =
  result = %{ "to": %transaction.to, "data": %transaction.data }
  if sender =? transaction.sender:
    result["from"] = %sender
  if nonce =? transaction.nonce:
    result["nonce"] = %nonce
  if chainId =? transaction.chainId:
    result["chainId"] = %chainId
  if gasPrice =? transaction.gasPrice:
    result["gasPrice"] = %gasPrice
  if gasLimit =? transaction.gasLimit:
    result["gas"] = %gasLimit

# BlockTag

func `%`*(blockTag: BlockTag): JsonNode =
  %($blockTag)
