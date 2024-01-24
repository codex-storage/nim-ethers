# import std/json
import std/strformat
import std/strutils
import std/sugar
# import pkg/eth/common/eth_types_json_serialization
import pkg/chronicles except fromJson, `%`, `%*`, toJson
import pkg/json_rpc/jsonmarshal
import pkg/questionable/results
import pkg/stew/byteutils
import ../../basics
import ../../transaction
import ../../blocktag
import ../../provider
import ./json

export jsonmarshal
export json
export chronicles except fromJson, `%`, `%*`, toJson

# {.push raises: [].}

type JsonSerializationError = object of EthersError

func toException*(v: ref CatchableError): ref SerializationError = (ref SerializationError)(msg: v.msg)

template raiseSerializationError(message: string) =
  raise newException(JsonSerializationError, message)

proc getOrRaise*[T, E](self: ?!T, exc: typedesc[E]): T {.raises: [E].} =
  let val = self.valueOr:
    raise newException(E, self.error.msg)
  val

proc expectFields(json: JsonNode, expectedFields: varargs[string]) =
  for fieldName in expectedFields:
    if not json.hasKey(fieldName):
      raiseSerializationError("'" & fieldName & "' field not found in " & $json)

# func fromJson*(T: type, json: JsonNode): T
# func fromJson*[T](json: JsonNode, result: var Option[T])
# func fromJson*[T](json: JsonNode, result: var seq[T])
# func fromJson*(json: JsonNode, result var T): T



# byte sequence

# func `%`*(bytes: seq[byte]): JsonNode =
#   %("0x" & bytes.toHex)

# func fromJson*(json: JsonNode, result: var seq[byte]) =
#   result = hexToSeqByte(json.getStr())

# byte arrays

# func `%`*[N](bytes: array[N, byte]): JsonNode =
#   %("0x" & bytes.toHex)

# func fromJson*[N](json: JsonNode, result: var array[N, byte]) =
#   hexToByteArray(json.getStr(), result)

# func fromJson*[N](json: JsonNode, result: var seq[array[N, byte]]) =
#   for elem in json.getElems:
#     var byteArr: array[N, byte]
#     fromJson(elem, byteArr)
#     result.add byteArr

# Address

func `%`*(address: Address): JsonNode =
  %($address)

# func fromJson(jsonVal: string, result: var Address) =
#   without address =? Address.init(jsonVal):
#     raiseSerializationError "Failed to convert '" & jsonVal & "' to Address"
#   result = address

# func fromJson*(json: JsonNode, result: var Address) =
#   let val = json.getStr
#   fromJson(val, result)

proc readValue*(r: var JsonReader[JrpcConv], result: var Address)
               {.raises: [SerializationError, IOError].} =
  var val = r.readValue(string)
  without address =? Address.init(val):
    raiseSerializationError "Failed to convert '" & val & "' to Address"
  result = address

proc writeValue*(
  writer: var JsonWriter[JrpcConv],
  value: Address
) {.raises:[IOError].} =
  writer.writeValue(%value)

# Filter
func `%`*(filter: Filter): JsonNode =
  %*{
    "fromBlock": filter.fromBlock,
    "toBlock": filter.toBlock
  }

proc writeValue*(
  writer: var JsonWriter[JrpcConv],
  value: Filter
) {.raises:[IOError].} =
  writer.writeValue(%value)

# EventFilter
func `%`*(filter: EventFilter): JsonNode =
  %*{
    "address": filter.address,
    "topics": filter.topics
  }
proc writeValue*(
  writer: var JsonWriter[JrpcConv],
  value: EventFilter
) {.raises:[IOError].} =
  writer.writeValue(%value)

# UInt256

# func `%`*(integer: UInt256): JsonNode =
#   %("0x" & toHex(integer))

# func fromJson*(json: JsonNode, result: var UInt256) =
#   result = UInt256.fromHex(json.getStr())

proc writeValue*(
    w: var JsonWriter, value: StUint) {.inline, raises: [IOError].} =
  w.writeValue $value

proc readValue*(
    r: var JsonReader, value: var StUint
) {.inline, raises: [IOError, SerializationError].} =
  let json = r.readValue(JsonNode)
  value = typeof(value).fromJson(json).getOrRaise(SerializationError)

# # TransactionType

# func fromJson*(json: JsonNode, result: var TransactionType) =
#   let val = fromHex[int](json.getStr)
#   result = TransactionType(val)

# func `%`*(txType: TransactionType): JsonNode =
#   %("0x" & txType.int.toHex(1))

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

proc writeValue*(
  writer: var JsonWriter[JrpcConv],
  value: Transaction
) {.raises:[IOError].} =
  writer.writeValue(%value)

# Block
# func fromJson*(json: JsonNode, result: var Block) {.raises: [JsonSerializationError].} =
#   var number: ?UInt256
#   var timestamp: UInt256
#   var hash: ?BlockHash
#   expectFields json, "number", "timestamp", "hash"
#   fromJson(json{"number"}, number)
#   fromJson(json{"timestamp"}, timestamp)
#   fromJson(json{"hash"}, hash)
#   result = Block(number: number, timestamp: timestamp, hash: hash)

proc readValue*(r: var JsonReader[JrpcConv], result: var Option[Block])
               {.raises: [SerializationError, IOError].} =
  var json = r.readValue(JsonNode)
  if json.isNil or json.kind == JNull:
    result = none Block

  # result = some Block()
  # result.number = Json.decode(result{"number"}, Option[UInt256])
  result = Option[Block].fromJson(json).getOrRaise(SerializationError)
  # without val =? Option[Block].fromJson(json) #.mapErr(e => newException(SerializationError, e.msg))
  # without blk =? Option[Block].fromJson(json), error:
  #   warn "failed to deserialize into Option[Block]", json
  #   result = none Block
  # result = blk
  # if json.isNil or json.kind == JNull:
  #   result = none Block
  # var res: Block
  # fromJson(Block, json, res)
  # result = some res

# BlockTag

# func `%`*(blockTag: BlockTag): JsonNode =
#   %($blockTag)

proc writeValue*(
  writer: var JsonWriter[JrpcConv],
  value: BlockTag
) {.raises:[IOError].} =
  writer.writeValue($value)

proc readValue*(r: var JsonReader[JrpcConv],
                result: var BlockTag) {.raises:[SerializationError, IOError].} =
  var json = r.readValue(JsonNode)
  result = BlockTag.fromJson(json).getOrRaise(SerializationError)

# Log

# func fromJson*(json: JsonNode, result: var Log) =
#   expectFields json, "data", "topics"

#   var data: seq[byte]
#   var topics: seq[Topic]
#   fromJson(json["data"], data)
#   fromJson(json["topics"], topics)
#   result = Log(data: data, topics: topics)

# TransactionStatus

# func fromJson*(json: JsonNode, result: var TransactionStatus) =
#   let val = fromHex[int](json.getStr)
#   result = TransactionStatus(val)

# func `%`*(status: TransactionStatus): JsonNode =
#   %("0x" & status.int.toHex(1))

# PastTransaction

proc readValue*(r: var JsonReader[JrpcConv], result: var Option[PastTransaction])
               {.raises: [SerializationError, IOError].} =
  var json = r.readValue(JsonNode)
  result = Option[PastTransaction].fromJson(json).getOrRaise(SerializationError)

# func fromJson*(json: JsonNode, result: var PastTransaction) =
#   # Deserializes a past transaction, eg eth_getTransactionByHash.
#   # Spec: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactionbyhash
#   json.expectFields "blockHash", "blockNumber", "from", "gas", "gasPrice",
#                     "hash", "input", "nonce", "to", "transactionIndex", "value",
#                     "v", "r", "s"

#   result = PastTransaction(
#     blockHash: BlockHash.fromJson(json["blockHash"]), #, "blockHash"),
#     blockNumber: UInt256.fromJson(json["blockNumber"]), #, "blockNumber"),
#     sender: Address.fromJson(json["from"]), #, "from"),
#     gas: UInt256.fromJson(json["gas"]), #, "gas"),
#     gasPrice: UInt256.fromJson(json["gasPrice"]), #, "gasPrice"),
#     hash: TransactionHash.fromJson(json["hash"]), #, "hash"),
#     input: seq[byte].fromJson(json["input"]), #, "input"),
#     nonce: UInt256.fromJson(json["nonce"]), #, "nonce"),
#     to: Address.fromJson(json["to"]), #, "to"),
#     transactionIndex: UInt256.fromJson(json["transactionIndex"]), #, "transactionIndex"),
#     value: UInt256.fromJson(json["value"]), #, "value"),
#     v: UInt256.fromJson(json["v"]), #, "v"),
#     r: UInt256.fromJson(json["r"]), #, "r"),
#     s: UInt256.fromJson(json["s"]) #, "s"),
#   )
#   if json.hasKey("type"):
#     result.transactionType = fromJson(?TransactionType, json["type"], "type")
#   if json.hasKey("chainId"):
#     result.chainId = fromJson(?UInt256, json["chainId"], "chainId")

# func `%`*(tx: PastTransaction): JsonNode =
#   let json = %*{
#     "blockHash": tx.blockHash,
#     "blockNumber": tx.blockNumber,
#     "from": tx.sender,
#     "gas": tx.gas,
#     "gasPrice": tx.gasPrice,
#     "hash": tx.hash,
#     "input": tx.input,
#     "nonce": tx.nonce,
#     "to": tx.to,
#     "transactionIndex": tx.transactionIndex,
#     "value": tx.value,
#     "v": tx.v,
#     "r": tx.r,
#     "s": tx.s
#   }
#   if txType =? tx.transactionType:
#     json["type"] = %txType
#   if chainId =? tx.chainId:
#     json["chainId"] = %chainId
#   return json

# TransactionReceipt

proc readValue*(r: var JsonReader[JrpcConv], result: var Option[TransactionReceipt])
               {.raises: [SerializationError, IOError].} =
  var json = r.readValue(JsonNode)
  result = Option[TransactionReceipt].fromJson(json).getOrRaise(SerializationError)

# func fromJson*(json: JsonNode, result: var TransactionReceipt) =
#   # Deserializes a transaction receipt, eg eth_getTransactionReceipt.
#   # Spec: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactionreceipt
#   json.expectFields "transactionHash", "transactionIndex", "cumulativeGasUsed",
#                     "effectiveGasPrice", "gasUsed", "logs", "logsBloom", "type",
#                     "status"

#   result = TransactionReceipt(
#     transactionHash: fromJson(TransactionHash, json["transactionHash"], "transactionHash"),
#     transactionIndex: UInt256.fromJson(json["transactionIndex"], "transactionIndex"),
#     blockHash: fromJson(?BlockHash, json["blockHash"], "blockHash"),
#     blockNumber: fromJson(?UInt256, json["blockNumber"], "blockNumber"),
#     sender: fromJson(?Address, json["from"], "from"),
#     to: fromJson(?Address, json["to"], "to"),
#     cumulativeGasUsed: UInt256.fromJson(json["cumulativeGasUsed"], "cumulativeGasUsed"),
#     effectiveGasPrice: fromJson(?UInt256, json["effectiveGasPrice"], "effectiveGasPrice"),
#     gasUsed: UInt256.fromJson(json["gasUsed"], "gasUsed"),
#     contractAddress: fromJson(?Address, json["contractAddress"], "contractAddress"),
#     logs: seq[Log].fromJson(json["logs"], "logs"),
#     logsBloom: seq[byte].fromJson(json["logsBloom"], "logsBloom"),
#     transactionType: TransactionType.fromJson(json["type"], "type"),
#     status: TransactionStatus.fromJson(json["status"], "status")
#   )

# func fromJson*[T](json: JsonNode, result: var Option[T]) =
#   if json.isNil or json.kind == JNull:
#     result = none T
#     return

#   var val: T
#   fromJson(json, val)
#   result = some val
#   # if val =? T.fromJson(json):
#   #   result = some val

# #   # result = none T

# func fromJson*[T](json: JsonNode, name = "", result: var seq[T]) =
#   if json.kind != JArray:
#     raiseSerializationError(fmt"Expected JArray to convert to seq, but got {json.kind}")

#   for elem in json.elems:
#     var v: T
#     fromJson(elem, name, v)
#     result.add(v)

# func fromJson*(T: type, json: JsonNode, name = ""): T =
#   fromJson(json, name, result)


# func fromJson*(T: type, json: JsonNode, name = ""): T =
#   fromJson(json, name, result)