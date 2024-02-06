
import std/json as stdjson except `%`, `%*`
import std/macros
import std/options
import std/sequtils
import std/sets
import std/strutils
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
  SerdeMode* = enum
    OptOut, ## serialize:   all object fields will be serialized, except fields marked with 'ignore'
            ## deserialize: all json keys will be deserialized, no error if extra json field
    OptIn,  ## serialize:   only object fields marked with serialize will be serialzied
            ## deserialize: only fields marked with deserialize will be deserialized
    Strict  ## serialize:   all object fields will be serialized, regardless if the field is marked with 'ignore'
            ## deserialize: object fields and json fields must match exactly
  SerdeFieldOptions = object
    key: string
    ignore: bool

template serialize*(key = "", ignore = false, mode = SerdeMode.OptOut) {.pragma.}
template deserialize*(key = "", ignore = false, mode = SerdeMode.OptOut) {.pragma.}

proc isDefault[T](paramValue: T): bool {.compileTime.} =
  var result = paramValue == T.default
  when T is SerdeMode:
    return paramValue == SerdeMode.OptOut
  return result

template expectMissingPragmaParam(value, pragma, name, msg) =
  static:
    when value.hasCustomPragma(pragma):
      const params = value.getCustomPragmaVal(pragma)
      for paramName, paramValue in params.fieldPairs:

        if paramName == name and not paramValue.isDefault:
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

template getSerdeFieldOptions(pragma, fieldName, fieldValue): SerdeFieldOptions =
  var opts = SerdeFieldOptions(key: fieldName, ignore: false)
  when fieldValue.hasCustomPragma(pragma):
    fieldValue.expectMissingPragmaParam(pragma, "mode",
      "Cannot set " & astToStr(pragma) & " 'mode' on '" & fieldName & "' field defintion.")
    let (key, ignore, _) = fieldValue.getCustomPragmaVal(pragma)
    opts.ignore = ignore
    if key != "":
      opts.key = key
  opts

template getSerdeMode(T, pragma): SerdeMode =
  when T.hasCustomPragma(pragma):
    T.expectMissingPragmaParam(pragma, "key",
      "Cannot set " & astToStr(pragma) & " 'key' on '" & $T &
      "' type definition.")
    T.expectMissingPragmaParam(pragma, "ignore",
      "Cannot set " & astToStr(pragma) & " 'ignore' on '" & $T &
      "' type definition.")
    let (_, _, mode) = T.getCustomPragmaVal(pragma)
    mode
  else:
    # Default mode -- when the type is NOT annotated with a
    # serialize/deserialize pragma.
    #
    # NOTE This may be different in the logic branch above, when the type is
    # annotated with serialize/deserialize but doesn't specify a mode. The
    # default in that case will fallback to the default mode specified in the
    # pragma signature (currently OptOut for both serialize and deserialize)
    #
    # Examples:
    # 1. type MyObj = object
    #    Type is not annotated, mode defaults to OptOut (as specified on the
    #    pragma signatures) for both serialization and deserializtion
    #
    # 2. type MyObj {.serialize, deserialize.} = object
    #    Type is annotated, mode defaults to OptIn for serialization and OptOut
    #    for deserialization
    when pragma == serialize:
      SerdeMode.OptIn
    elif pragma == deserialize:
      SerdeMode.OptOut

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

proc fromJson*[T: ref object or object](
  _: type T,
  json: JsonNode
): ?!T =

  when T is JsonNode:
    return success T(json)

  expectJsonKind(T, JObject, json)
  var res = when type(T) is ref: T.new() else: T.default
  let mode = T.getSerdeMode(deserialize)

  # ensure there's no extra fields in json
  if mode == SerdeMode.Strict:
    let extraFields = json.keysNotIn(res)
    if extraFields.len > 0:
      return failure newSerdeError("json field(s) missing in object: " & $extraFields)

  for name, value in fieldPairs(when type(T) is ref: res[] else: res):

    logScope:
      field = $T & "." & name
      mode

    let hasDeserializePragma = value.hasCustomPragma(deserialize)
    let opts = getSerdeFieldOptions(deserialize, name, value)
    let isOptionalValue = typeof(value) is Option
    var skip = false # workaround for 'continue' not supported in a 'fields' loop

    case mode:
    of Strict:
      if opts.key notin json:
        return failure newSerdeError("object field missing in json: " & opts.key)
      elif opts.ignore:
        # unable to figure out a way to make this a compile time check
        warn "object field marked as 'ignore' while in Strict mode, field will be deserialized anyway"

    of OptIn:
      if not hasDeserializePragma:
        debug "object field not marked as 'deserialize', skipping"
        skip = true
      elif opts.ignore:
        debug "object field marked as 'ignore', skipping"
        skip = true
      elif opts.key notin json and not isOptionalValue:
        return failure newSerdeError("object field missing in json: " & opts.key)

    of OptOut:
      if opts.ignore:
        debug "object field is opted out of deserialization ('igore' is set), skipping"
        skip = true
      elif hasDeserializePragma and opts.key == name:
        warn "object field marked as deserialize in OptOut mode, but 'ignore' not set, field will be deserialized"

    if not skip:

      if isOptionalValue:

        let jsonVal = json{opts.key}
        without parsed =? typeof(value).fromJson(jsonVal), e:
          debug "failed to deserialize field",
            `type` = $typeof(value),
            json = jsonVal,
            error = e.msg
          return failure(e)
        value = parsed

      # not Option[T]
      elif opts.key in json and
        jsonVal =? json{opts.key}.catch and
        not jsonVal.isNil:

        without parsed =? typeof(value).fromJson(jsonVal), e:
          debug "failed to deserialize field",
            `type` = $typeof(value),
            json = jsonVal,
            error = e.msg
          return failure(e)
        value = parsed

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
  jsn: string
): ?!JsonNode =
  return json.parseJson(jsn)

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


proc `%`*[T: object or ref object](obj: T): JsonNode =

  let jsonObj = newJObject()
  let o = when T is ref object: obj[]
          else: obj

  let mode = T.getSerdeMode(serialize)

  for name, value in o.fieldPairs:

    logScope:
      field = $T & "." & name
      mode

    let opts = getSerdeFieldOptions(serialize, name, value)
    const serializeField = value.hasCustomPragma(serialize)
    var skip = false # workaround for 'continue' not supported in a 'fields' loop

    case mode:
    of OptIn:
      if not serializeField:
        debug "object field not marked with serialize, skipping"
        skip = true
      elif opts.ignore:
        skip = true

    of OptOut:
      if opts.ignore:
        debug "object field opted out of serialization ('ignore' is set), skipping"
        skip = true
      elif serializeField and opts.key == name: # all serialize params are default
        warn "object field marked as serialize in OptOut mode, but 'ignore' not set, field will be serialized"

    of Strict:
      if opts.ignore:
        # unable to figure out a way to make this a compile time check
        warn "object field marked as 'ignore' while in Strict mode, field will be serialized anyway"

    if not skip:
      jsonObj[opts.key] = %value

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

proc toJson*[T](item: T): string = $(%item)

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
