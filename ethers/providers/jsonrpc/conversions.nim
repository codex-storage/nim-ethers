import std/json
import std/strutils
import pkg/json_rpc/jsonmarshal
import pkg/stew/byteutils
import ../../basics
import ../../transaction
import ../../blocktag
import ../../provider

export jsonmarshal

func fromJson*(T: type, json: JsonNode, name = ""): T =
  fromJson(json, name, result)

# byte sequence

func `%`*(bytes: seq[byte]): JsonNode =
  %("0x" & bytes.toHex)

func fromJson*(json: JsonNode, name: string, result: var seq[byte]) =
  result = hexToSeqByte(json.getStr())

# byte arrays

func `%`*[N](bytes: array[N, byte]): JsonNode =
  %("0x" & bytes.toHex)

func fromJson*[N](json: JsonNode, name: string, result: var array[N, byte]) =
  hexToByteArray(json.getStr(), result)

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

# Log

func fromJson*(json: JsonNode, name: string, result: var Log) =
  var data: seq[byte]
  var topics: seq[Topic]
  fromJson(json["data"], "data", data)
  fromJson(json["topics"], "topics", topics)
  result = Log(data: data, topics: topics)

# TransactionStatus

func fromJson*(json: JsonNode, name: string, result: var TransactionStatus) =
  let val = fromHex[int](json.getStr)
  result = TransactionStatus(val)

func `%`*(status: TransactionStatus): JsonNode =
  %(status.int.toHex)
