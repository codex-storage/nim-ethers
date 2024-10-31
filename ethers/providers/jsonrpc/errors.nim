import std/strutils
import pkg/stew/byteutils
import ../../basics
import ../../errors
import ../../provider
import ./conversions

export errors

{.push raises:[].}

type JsonRpcProviderError* = object of ProviderError

func extractErrorData(json: JsonNode): ?seq[byte] =
  if json.kind == JObject:
    if "message" in json and "data" in json:
      let message = json{"message"}.getStr()
      let hex = json{"data"}.getStr()
      if "reverted" in message and hex.startsWith("0x"):
        if data =? hexToSeqByte(hex).catch:
          return some data
    for key in json.keys:
      if data =? extractErrorData(json{key}):
        return some data

func new*(_: type JsonRpcProviderError, json: JsonNode): ref JsonRpcProviderError =
  let error = (ref JsonRpcProviderError)()
  if "message" in json:
    error.msg = json{"message"}.getStr
  error.data = extractErrorData(json)
  error

proc raiseJsonRpcProviderError*(
  message: string) {.raises: [JsonRpcProviderError].} =
  if json =? JsonNode.fromJson(message):
    raise JsonRpcProviderError.new(json)
  else:
    raise newException(JsonRpcProviderError, message)

template convertError*(body) =
  try:
    body
  except JsonRpcError as error:
    raiseJsonRpcProviderError(error.msg)
  except CatchableError as error:
    raiseJsonRpcProviderError(error.msg)

