import std/json
import std/strformat
import std/strutils
import std/typetraits
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

proc expectFields(json: JsonNode, expectedFields: varargs[string]) =
  for fieldName in expectedFields:
    if not json.hasKey(fieldName):
      raiseSerializationError(fmt"'{fieldName}' field not found in ${json}")

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

# TransactionType

func fromJson*(json: JsonNode, name: string, result: var TransactionType) =
  let val = fromHex[int](json.getStr)
  result = TransactionType(val)

func `%`*(txType: TransactionType): JsonNode =
  debugEcho "serializing tx type: ", txType, " to: 0x", txType.int.toHex(1)
  %("0x" & txType.int.toHex(1))

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
  if txType =? transaction.transactionType:
    result["type"] = %txType

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
  %("0x" & status.int.toHex(1))

# PastTransaction

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
  if json.hasKey("type"):
    result.transactionType = fromJson(?TransactionType, json["type"], "type")
  if json.hasKey("chainId"):
    result.chainId = fromJson(?UInt256, json["chainId"], "chainId")

func `%`*(tx: PastTransaction): JsonNode =
  let json = %*{
    "blockHash": tx.blockHash,
    "blockNumber": tx.blockNumber,
    "from": tx.sender,
    "gas": tx.gas,
    "gasPrice": tx.gasPrice,
    "hash": tx.hash,
    "input": tx.input,
    "nonce": tx.nonce,
    "to": tx.to,
    "transactionIndex": tx.transactionIndex,
    "value": tx.value,
    "v": tx.v,
    "r": tx.r,
    "s": tx.s
  }
  if txType =? tx.transactionType:
    json["type"] = %txType
  if chainId =? tx.chainId:
    json["chainId"] = %chainId
  return json

# TransactionReceipt

func fromJson*(json: JsonNode, name: string, result: var TransactionReceipt) =
  # Deserializes a transaction receipt, eg eth_getTransactionReceipt.
  # Spec: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactionreceipt
  json.expectFields "transactionHash", "transactionIndex", "cumulativeGasUsed",
                    "effectiveGasPrice", "gasUsed", "logs", "logsBloom", "type",
                    "status"

  result = TransactionReceipt(
    transactionHash: fromJson(TransactionHash, json["transactionHash"], "transactionHash"),
    transactionIndex: UInt256.fromJson(json["transactionIndex"], "transactionIndex"),
    blockHash: fromJson(?BlockHash, json["blockHash"], "blockHash"),
    blockNumber: fromJson(?UInt256, json["blockNumber"], "blockNumber"),
    sender: fromJson(?Address, json["from"], "from"),
    to: fromJson(?Address, json["to"], "to"),
    cumulativeGasUsed: UInt256.fromJson(json["cumulativeGasUsed"], "cumulativeGasUsed"),
    effectiveGasPrice: fromJson(?UInt256, json["effectiveGasPrice"], "effectiveGasPrice"),
    gasUsed: UInt256.fromJson(json["gasUsed"], "gasUsed"),
    contractAddress: fromJson(?Address, json["contractAddress"], "contractAddress"),
    logs: seq[Log].fromJson(json["logs"], "logs"),
    logsBloom: seq[byte].fromJson(json["logsBloom"], "logsBloom"),
    transactionType: TransactionType.fromJson(json["type"], "type"),
    status: TransactionStatus.fromJson(json["status"], "status")
  )
