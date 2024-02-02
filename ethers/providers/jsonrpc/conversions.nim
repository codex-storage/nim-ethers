import std/strformat
import std/strutils
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

{.push raises: [].}

proc getOrRaise*[T, E](self: ?!T, exc: typedesc[E]): T {.raises: [E].} =
  let val = self.valueOr:
    raise newException(E, self.error.msg)
  val

template mapFailure*[T, V, E](
    exp: Result[T, V],
    exc: typedesc[E],
): Result[T, ref CatchableError] =
  ## Convert `Result[T, E]` to `Result[E, ref CatchableError]`
  ##

  exp.mapErr(proc (e: V): ref CatchableError = (ref exc)(msg: e.msg))

# Address

func `%`*(address: Address): JsonNode =
  %($address)

func fromJson(_: type Address, json: JsonNode): ?!Address =
  expectJsonKind(Address, JString, json)
  without address =? Address.init(json.getStr), error:
    return failure newException(SerializationError,
      "Failed to convert '" & $json & "' to Address: " & error.msg)
  success address

# UInt256

func `%`*(integer: UInt256): JsonNode =
  %("0x" & toHex(integer))

func fromJson*(_: type UInt256, json: JsonNode): ?!UInt256 =
  without result =? UInt256.fromHex(json.getStr()).catch, error:
    return UInt256.failure error.msg
  success result

# Transaction

# TODO: add option that ignores none Option[T]
# TODO: add name option (gasLimit => gas, sender => from)
func `%`*(transaction: Transaction): JsonNode =
  result = %*{
    "to": transaction.to,
    "data": %transaction.data,
    "value": %transaction.value
  }
  if sender =? transaction.`from`:
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

# TransactionStatus | TransactionType

func `%`*(e: TransactionStatus | TransactionType): JsonNode =
  % ("0x" & e.int8.toHex(1))

proc fromJson*[E: TransactionStatus | TransactionType](
  T: type E,
  json: JsonNode
): ?!T =
  expectJsonKind(string, JString, json)
  let integer = ? fromHex[int](json.str).catch.mapFailure(SerializationError)
  success T(integer)

## Generic conversions to use nim-json instead of nim-json-serialization for
## json rpc serialization purposes
##  writeValue => `%`
##  readValue  => fromJson

proc writeValue*[T: not JsonNode](
  writer: var JsonWriter[JrpcConv],
  value: T) {.raises:[IOError].} =

  writer.writeValue(%value)

proc readValue*[T: not JsonNode](
  r: var JsonReader[JrpcConv],
  result: var T) {.raises: [SerializationError, IOError].} =

  var json = r.readValue(JsonNode)
  result = T.fromJson(json).getOrRaise(SerializationError)
