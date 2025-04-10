import ../../basics
import ../../provider
import ./encoding

type ConvertCustomErrors* =
    proc(error: ref ProviderError): ref EthersError {.gcsafe, raises:[].}

func customErrorConversion*(ErrorTypes: type tuple): ConvertCustomErrors =
  func convert(error: ref ProviderError): ref EthersError =
    if data =? error.data:
      for e in ErrorTypes.default.fields:
        if error =? typeof(e).decode(data):
          return error
    return error
  convert
