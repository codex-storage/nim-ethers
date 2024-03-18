import pkg/stew/byteutils
import ../../provider
import ./conversions

type JsonRpcProviderError* = object of ProviderError

func new(_: type JsonRpcProviderError, json: JsonNode): ref JsonRpcProviderError =
  let error = (ref JsonRpcProviderError)()
  if "message" in json:
    error.msg = json{"message"}.getStr
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

