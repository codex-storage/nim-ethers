
import std/json as stdjson except `%`, `%*`
import std/macros
import std/options
import std/sequtils
import std/sets
import std/strutils
# import std/strformat
import std/tables
import std/typetraits
import pkg/chronicles except toJson
import pkg/contractabi
import pkg/stew/byteutils
import pkg/stint
import pkg/questionable
import pkg/questionable/results

import ../../basics

export stdjson except `%`, `%*`, parseJson
export chronicles except toJson
export sets

{.push raises: [].}

logScope:
  topics = "json de/serialization"

type
  SerdeError* = object of EthersError
  UnexpectedKindError* = object of SerdeError
  DeserializeMode* = enum
    Default,  ## objects can have more or less fields than json
    OptIn,    ## json must have fields marked with {.serialize.}
    Strict    ## object fields and json fields must match exactly

# template serializeAll* {.pragma.}
template serialize*(key = "", ignore = false) {.pragma.}
template deserialize*(key = "", mode = DeserializeMode.Default) {.pragma.}

template expectEmptyPragma(value, pragma, msg) =
  static:
    when value.hasCustomPragma(pragma):
      const params = value.getCustomPragmaVal(pragma)
      for param in params.fields:
        if param != typeof(param).default:
          raiseAssert(msg)

template expectMissingPragmaParam(value, pragma, name, msg) =
  static:
    when value.hasCustomPragma(pragma):
      const params = value.getCustomPragmaVal(pragma)
      for paramName, paramValue in params.fieldPairs:
        if paramName == name and paramValue != typeof(paramValue).default:
          raiseAssert(msg)

proc mapErrTo[E1: ref CatchableError, E2: SerdeError](
  e1: E1,
  _: type E2,
  msg: string = e1.msg): ref E2 =

  return newException(E2, msg, e1)

proc newSerdeError(msg: string): ref SerdeError =
  newException(SerdeError, msg)

proc newUnexpectedKindError(
  expectedType: type,
  expectedKinds: string,
  json: JsonNode
): ref UnexpectedKindError =
  let kind = if json.isNil: "nil"
             else: $json.kind
  newException(UnexpectedKindError,
    "deserialization to " & $expectedType & " failed: expected " &
    expectedKinds & " but got " & $kind)

proc newUnexpectedKindError(
  expectedType: type,
  expectedKinds: set[JsonNodeKind],
  json: JsonNode
): ref UnexpectedKindError =
  newUnexpectedKindError(expectedType, $expectedKinds, json)

proc newUnexpectedKindError(
  expectedType: type,
  expectedKind: JsonNodeKind,
  json: JsonNode
): ref UnexpectedKindError =
  newUnexpectedKindError(expectedType, {expectedKind}, json)

template expectJsonKind(
  expectedType: type,
  expectedKinds: set[JsonNodeKind],
  json: JsonNode
) =
  if json.isNil or json.kind notin expectedKinds:
    return failure(newUnexpectedKindError(expectedType, expectedKinds, json))

template expectJsonKind*(
  expectedType: type,
  expectedKind: JsonNodeKind,
  json: JsonNode
) =
  expectJsonKind(expectedType, {expectedKind}, json)

proc fieldKeys[T](obj: T): seq[string] =
  for name, _ in fieldPairs(when type(T) is ref: obj[] else: obj):
    result.add name

func keysNotIn[T](json: JsonNode, obj: T): HashSet[string] =
  let jsonKeys = json.keys.toSeq.toHashSet
  let objKeys = obj.fieldKeys.toHashSet
  difference(jsonKeys, objKeys)

proc fromJson*(
  T: type enum,
  json: JsonNode
): ?!T =
  expectJsonKind(string, JString, json)
  without val =? parseEnum[T](json.str).catch, error:
    return failure error.mapErrTo(SerdeError)
  return success val

proc fromJson*(
  _: type string,
  json: JsonNode
): ?!string =
  if json.isNil:
    return failure newSerdeError("'json' expected, but was nil")
  elif json.kind == JNull:
    return success("null")
  elif json.isNil or json.kind != JString:
    return failure newUnexpectedKindError(string, JString, json)
  catch json.getStr

proc fromJson*(
  _: type bool,
  json: JsonNode
): ?!bool =
  expectJsonKind(bool, JBool, json)
  catch json.getBool

proc fromJson*(
  _: type int,
  json: JsonNode
): ?!int =
  expectJsonKind(int, JInt, json)
  catch json.getInt

proc fromJson*[T: SomeInteger](
  _: type T,
  json: JsonNode
): ?!T =
  when T is uint|uint64 or (not defined(js) and int.sizeof == 4):
    expectJsonKind(T, {JInt, JString}, json)
    case json.kind
    of JString:
      without x =? parseBiggestUInt(json.str).catch, error:
        return failure newSerdeError(error.msg)
      return success cast[T](x)
    else:
      return success T(json.num)
  else:
    expectJsonKind(T, {JInt}, json)
    return success cast[T](json.num)

proc fromJson*[T: SomeFloat](
  _: type T,
  json: JsonNode
): ?!T =
  expectJsonKind(T, {JInt, JFloat, JString}, json)
  if json.kind == JString:
    case json.str
    of "nan":
      let b = NaN
      return success T(b)
      # dst = NaN # would fail some tests because range conversions would cause CT error
      # in some cases; but this is not a hot-spot inside this branch and backend can optimize this.
    of "inf":
      let b = Inf
      return success T(b)
    of "-inf":
      let b = -Inf
      return success T(b)
    else:
      let err = newUnexpectedKindError(T, "'nan|inf|-inf'", json)
      return failure(err)
  else:
    if json.kind == JFloat:
      return success T(json.fnum)
    else:
      return success T(json.num)

proc fromJson*(
  _: type seq[byte],
  json: JsonNode
): ?!seq[byte] =
  expectJsonKind(seq[byte], JString, json)
  hexToSeqByte(json.getStr).catch

proc fromJson*[N: static[int], T: array[N, byte]](
  _: type T,
  json: JsonNode
): ?!T =
  expectJsonKind(T, JString, json)
  T.fromHex(json.getStr).catch

proc fromJson*[T: distinct](
  _: type T,
  json: JsonNode
): ?!T =
  success T(? T.distinctBase.fromJson(json))

proc fromJson*[N: static[int], T: StUint[N]](
  _: type T,
  json: JsonNode
): ?!T =
  expectJsonKind(T, JString, json)
  let jsonStr = json.getStr
  let prefix = jsonStr[0..1].toLowerAscii
  case prefix:
  of "0x": catch parse(jsonStr, T, 16)
  of "0o": catch parse(jsonStr, T, 8)
  of "0b": catch parse(jsonStr, T, 2)
  else: catch parse(jsonStr, T)

proc fromJson*[T](
  _: type Option[T],
  json: JsonNode
): ?! Option[T] =
  if json.isNil or json.kind == JNull:
    return success(none T)
  without val =? T.fromJson(json), error:
    return failure(error)
  success(val.some)

proc fromJson*[T](
  _: type seq[T],
  json: JsonNode
): ?! seq[T] =
  expectJsonKind(seq[T], JArray, json)
  var arr: seq[T] = @[]
  for elem in json.elems:
    arr.add(? T.fromJson(elem))
  success arr

template getDeserializationKey(fieldName, fieldValue): string =
  when fieldValue.hasCustomPragma(deserialize):
    fieldValue.expectMissingPragmaParam(deserialize, "mode",
                                    "Cannot set 'mode' on field defintion.")
    let (key, mode) = fieldValue.getCustomPragmaVal(deserialize)
    if key != "": key
    else: fieldName
  else: fieldName

template getDeserializationMode(T): DeserializeMode =
  when T.hasCustomPragma(deserialize):
    T.expectMissingPragmaParam(deserialize, "key",
                               "Cannot set 'key' on object definition.")
    T.getCustomPragmaVal(deserialize)[1] # mode = second pragma param
  else:
    DeserializeMode.Default

proc fromJson*[T: ref object or object](
  _: type T,
  json: JsonNode
): ?!T =

  when T is JsonNode:
    return success T(json)

  expectJsonKind(T, JObject, json)
  var res = when type(T) is ref: T.new() else: T.default
  let mode = T.getDeserializationMode()

  for name, value in fieldPairs(when type(T) is ref: res[] else: res):
    logScope:
      field = $T & "." & name
      mode

    let key = getDeserializationKey(name, value)
    var skip = false # workaround for 'continue' not supported in a 'fields' loop

    if mode == Strict and key notin json:
      return failure newSerdeError("object field missing in json: " & key)

    if mode == OptIn:
      if not value.hasCustomPragma(deserialize):
        debug "object field not marked as 'deserialize', skipping", name = name
        # use skip as workaround for 'continue' not supported in a 'fields' loop
        skip = true
      elif key notin json:
        return failure newSerdeError("object field missing in json: " & key)

    if key in json and
       jsonVal =? json{key}.catch and
       not jsonVal.isNil and
       not skip:

      without parsed =? type(value).fromJson(jsonVal), e:
        warn "failed to deserialize field",
          `type` = $typeof(value),
          json = jsonVal,
          error = e.msg
        return failure(e)
      value = parsed

    elif mode == DeserializeMode.Default:
      debug "object field missing in json, skipping", key, json

    # ensure there's no extra fields in json
    if mode == DeserializeMode.Strict:
      let extraFields = json.keysNotIn(res)
      if extraFields.len > 0:
        return failure newSerdeError("json field(s) missing in object: " & $extraFields)

  success(res)

proc parseJson*(json: string): ?!JsonNode =
  ## fix for nim raising Exception
  try:
    return stdjson.parseJson(json).catch
  except Exception as e:
    return err newException(CatchableError, e.msg)

proc fromJson*[T: ref object or object](
  _: type T,
  bytes: seq[byte]
): ?!T =
  let json = ? parse(string.fromBytes(bytes))
  T.fromJson(json)

proc fromJson*(
  _: type JsonNode,
  json: string
): ?!JsonNode =
  return parse(json)

proc fromJson*[T: ref object or object](
  _: type T,
  jsn: string
): ?!T =
  let jsn = ? json.parseJson(jsn) # full qualification required in-module only
  T.fromJson(jsn)

func `%`*(s: string): JsonNode = newJString(s)

func `%`*(n: uint): JsonNode =
  if n > cast[uint](int.high):
    newJString($n)
  else:
    newJInt(BiggestInt(n))

func `%`*(n: int): JsonNode = newJInt(n)

func `%`*(n: BiggestUInt): JsonNode =
  if n > cast[BiggestUInt](BiggestInt.high):
    newJString($n)
  else:
    newJInt(BiggestInt(n))

func `%`*(n: BiggestInt): JsonNode = newJInt(n)

func `%`*(n: float): JsonNode =
  if n != n: newJString("nan")
  elif n == Inf: newJString("inf")
  elif n == -Inf: newJString("-inf")
  else: newJFloat(n)

func `%`*(b: bool): JsonNode = newJBool(b)

func `%`*(keyVals: openArray[tuple[key: string, val: JsonNode]]): JsonNode =
  if keyVals.len == 0: return newJArray()
  let jObj = newJObject()
  for key, val in items(keyVals): jObj.fields[key] = val
  jObj

template `%`*(j: JsonNode): JsonNode = j

func `%`*[T](table: Table[string, T]|OrderedTable[string, T]): JsonNode =
  let jObj = newJObject()
  for k, v in table: jObj[k] = ? %v
  jObj

func `%`*[T](opt: Option[T]): JsonNode =
  if opt.isSome: %(opt.get) else: newJNull()


func `%`*[T: object or ref object](obj: T): JsonNode =

  # T.expectMissingPragma(serialize, "Invalid pragma on object definition.")

  let jsonObj = newJObject()
  let o = when T is ref object: obj[]
          else: obj

  T.expectEmptyPragma(serialize, "Cannot specify 'key' or 'ignore' on object defition")

  const serializeAllFields = T.hasCustomPragma(serialize)

  for name, value in o.fieldPairs:
    # TODO: move to %
    # value.expectMissingPragma(deserializeMode, "Invalid pragma on field definition.")
    # static:
    const serializeField = value.hasCustomPragma(serialize)
    when serializeField:
      let (keyOverride, ignore) = value.getCustomPragmaVal(serialize)
      if not ignore:
        let key = if keyOverride != "": keyOverride
                  else: name
        jsonObj[key] = %value

    elif serializeAllFields:
      jsonObj[name] = %value

  jsonObj

proc `%`*(o: enum): JsonNode = % $o

func `%`*(stint: StInt|StUint): JsonNode = %stint.toString

func `%`*(cstr: cstring): JsonNode = % $cstr

func `%`*(arr: openArray[byte]): JsonNode = % arr.to0xHex

func `%`*[T](elements: openArray[T]): JsonNode =
  let jObj = newJArray()
  for elem in elements: jObj.add(%elem)
  jObj

func `%`*[T: distinct](id: T): JsonNode =
  type baseType = T.distinctBase
  % baseType(id)

func toJson*[T](item: T): string = $(%item)

proc toJsnImpl(x: NimNode): NimNode =
  case x.kind
  of nnkBracket: # array
    if x.len == 0: return newCall(bindSym"newJArray")
    result = newNimNode(nnkBracket)
    for i in 0 ..< x.len:
      result.add(toJsnImpl(x[i]))
    result = newCall(bindSym("%", brOpen), result)
  of nnkTableConstr: # object
    if x.len == 0: return newCall(bindSym"newJObject")
    result = newNimNode(nnkTableConstr)
    for i in 0 ..< x.len:
      x[i].expectKind nnkExprColonExpr
      result.add newTree(nnkExprColonExpr, x[i][0], toJsnImpl(x[i][1]))
    result = newCall(bindSym("%", brOpen), result)
  of nnkCurly: # empty object
    x.expectLen(0)
    result = newCall(bindSym"newJObject")
  of nnkNilLit:
    result = newCall(bindSym"newJNull")
  of nnkPar:
    if x.len == 1: result = toJsnImpl(x[0])
    else: result = newCall(bindSym("%", brOpen), x)
  else:
    result = newCall(bindSym("%", brOpen), x)

macro `%*`*(x: untyped): JsonNode =
  ## Convert an expression to a JsonNode directly, without having to specify
  ## `%` for every element.
  result = toJsnImpl(x)
