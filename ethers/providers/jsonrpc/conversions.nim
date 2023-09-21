import std/json
import std/strformat
import std/strutils
import pkg/json_rpc/jsonmarshal
import pkg/stew/byteutils
import ../../basics
import ../../transaction
import ../../blocktag
import ../../provider

export jsonmarshal

type JsonSerializationError = object of EthersError

template raiseSerializationError(message: string) =
  raise newException(JsonSerializationError, message)

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
  if not (json.hasKey("data") and json.hasKey("topics")):
    raise newException(ValueError, "'data' and/or 'topics' fields not found")

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

# Transaction

proc expectFields(json: JsonNode, expectedFields: varargs[string]) =
  for fieldName in expectedFields:
    if not json.hasKey(fieldName):
      raiseSerializationError(fmt"'{fieldName}' field not found in ${json}")

func fromJson*(json: JsonNode, name: string, result: var PastTransaction) =
  # Deserializes a past transaction, eg eth_getTransactionByHash.
  # Spec: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactionbyhash
  json.expectFields "blockHash", "blockNumber", "from", "gas", "gasPrice",
                    "hash", "input", "nonce", "to", "transactionIndex", "value",
                    "v", "r", "s"

  result = PastTransaction(
    blockHash: BlockHash.fromJson(json["blockHash"], "blockHash"),
    blockNumber: UInt256.fromJson(json["blockNumber"], "blockNumber"),
    sender: Address.fromJson(json["from"], "from"),
    gas: UInt256.fromJson(json["gas"], "gas"),
    gasPrice: UInt256.fromJson(json["gasPrice"], "gasPrice"),
    hash: TransactionHash.fromJson(json["hash"], "hash"),
    input: seq[byte].fromJson(json["input"], "input"),
    nonce: UInt256.fromJson(json["nonce"], "nonce"),
    to: Address.fromJson(json["to"], "to"),
    transactionIndex: UInt256.fromJson(json["transactionIndex"], "transactionIndex"),
    value: UInt256.fromJson(json["value"], "value"),
    v: UInt256.fromJson(json["v"], "v"),
    r: UInt256.fromJson(json["r"], "r"),
    s: UInt256.fromJson(json["s"], "s"),
  )