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

# Address

func `%`*(address: Address): JsonNode =
  %($address)

func fromJson(_: type Address, json: JsonNode): ?!Address =
  expectJsonKind(Address, JString, json)
  without address =? Address.init(json.getStr), error:
    return failure newException(SerializationError,
      "Failed to convert '" & $json & "' to Address: " & error.msg)
  success address


# proc readValue*(
#   r: var JsonReader[JrpcConv],
#   result: var Address) {.raises: [SerializationError, IOError].} =

#   let json = r.readValue(JsonNode)
#   result = Address.fromJson(json).getOrRaise(SerializationError)

# proc writeValue*(
#   writer: var JsonWriter[JrpcConv],
#   value: Address
# ) {.raises:[IOError].} =
#   writer.writeValue(%value)

# Filter
# func `%`*(filter: Filter): JsonNode =
#   %*{
#     "fromBlock": filter.fromBlock,
#     "toBlock": filter.toBlock
#   }

# proc writeValue*(
#   writer: var JsonWriter[JrpcConv],
#   value: Filter
# ) {.raises:[IOError].} =
#   writer.writeValue(%value)

# EventFilter
# func `%`*(filter: EventFilter): JsonNode =
#   %*{
#     "address": filter.address,
#     "topics": filter.topics
#   }
# proc writeValue*(
#   writer: var JsonWriter[JrpcConv],
#   value: EventFilter
# ) {.raises:[IOError].} =
#   writer.writeValue(%value)

# UInt256

func `%`*(integer: UInt256): JsonNode =
  %("0x" & toHex(integer))

func fromJson*(_: type UInt256, json: JsonNode): ?!UInt256 =
  without result =? UInt256.fromHex(json.getStr()).catch, error:
    return UInt256.failure error.msg
  success result

# proc writeValue*(
#     w: var JsonWriter, value: StUint) {.inline, raises: [IOError].} =
#   echo "writing UInt256 value to hex: ", value.toString, ", in hex: ", value.toHex
#   w.writeValue %value

# proc readValue*(
#     r: var JsonReader, value: var StUint
# ) {.inline, raises: [IOError, SerializationError].} =
#   let json = r.readValue(JsonNode)
#   value = typeof(value).fromJson(json).getOrRaise(SerializationError)

# TransactionHash

# proc readValue*(
#     r: var JsonReader, value: var TransactionHash
# ) {.inline, raises: [IOError, SerializationError].} =
#   let json = r.readValue(JsonNode)
#   value = TransactionHash.fromJson(json).getOrRaise(SerializationError)

# Transaction

# proc writeValue*(
#   writer: var JsonWriter[JrpcConv],
#   value: Transaction
# ) {.raises:[IOError].} =
#   writer.writeValue(%value)

# Block

# proc readValue*(r: var JsonReader[JrpcConv], result: var Option[Block])
#                {.raises: [SerializationError, IOError].} =
#   var json = r.readValue(JsonNode)
#   if json.isNil or json.kind == JNull:
#     result = none Block

#   result = Option[Block].fromJson(json).getOrRaise(SerializationError)

# BlockTag

# proc writeValue*(
#   writer: var JsonWriter[JrpcConv],
#   value: BlockTag
# ) {.raises:[IOError].} =
#   writer.writeValue($value)

func `%`*(tag: BlockTag): JsonNode =
  % $tag

func fromJson*(_: type BlockTag, json: JsonNode): ?!BlockTag =
  expectJsonKind(BlockTag, JString, json)
  let jsonVal = json.getStr
  if jsonVal[0..1].toLowerAscii == "0x":
    without blkNum =? UInt256.fromHex(jsonVal).catch, error:
      return BlockTag.failure error.msg
    return success BlockTag.init(blkNum)

  case jsonVal:
  of "earliest": return success BlockTag.earliest
  of "latest": return success BlockTag.latest
  of "pending": return success BlockTag.pending
  else: return failure newException(SerializationError,
      "Failed to convert '" & $json &
      "' to BlockTag: must be one of 'earliest', 'latest', 'pending'")

# proc readValue*(r: var JsonReader[JrpcConv],
#                 result: var BlockTag) {.raises:[SerializationError, IOError].} =
#   var json = r.readValue(JsonNode)
#   result = BlockTag.fromJson(json).getOrRaise(SerializationError)

# PastTransaction

# proc readValue*(r: var JsonReader[JrpcConv], result: var Option[PastTransaction])
#                {.raises: [SerializationError, IOError].} =
#   var json = r.readValue(JsonNode)
#   result = Option[PastTransaction].fromJson(json).getOrRaise(SerializationError)

# TransactionReceipt

# proc readValue*(r: var JsonReader[JrpcConv], result: var Option[TransactionReceipt])
#                {.raises: [SerializationError, IOError].} =
#   var json = r.readValue(JsonNode)
#   result = Option[TransactionReceipt].fromJson(json).getOrRaise(SerializationError)

proc writeValue*[T: not JsonNode](
  writer: var JsonWriter[JrpcConv],
  value: T) {.raises:[IOError].} =

  writer.writeValue(%value)

proc readValue*[T: not JsonNode](
  r: var JsonReader[JrpcConv],
  result: var T) {.raises: [SerializationError, IOError].} =

  var json = r.readValue(JsonNode)
  # when T of JsonNode:
  #   result = json
  #   return
  # echo "[conversions.readValue] converting '", json, "' into ", T
  static: echo "[conversions.readValue] converting into ", T
  result = T.fromJson(json).getOrRaise(SerializationError)
