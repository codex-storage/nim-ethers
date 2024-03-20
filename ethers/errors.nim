import pkg/contractabi
import pkg/contractabi/selector
import ./basics

type SolidityError* = object of EthersError

{.push raises:[].}

template errors*(types) {.pragma.}

func selector(E: type): FunctionSelector =
  when compiles(E.arguments):
    selector($E, typeof(E.arguments))
  else:
    selector($E, tuple[])

func matchesSelector(E: type, data: seq[byte]): bool =
  const selector = E.selector.toArray
  data.len >= 4 and selector[0..<4] == data[0..<4]

func decodeArguments(E: type, data: seq[byte]): auto =
  AbiDecoder.decode(data[4..^1], E.arguments)

func decode*[E: SolidityError](_: type E, data: seq[byte]): ?!(ref E) =
  if not E.matchesSelector(data):
    return failure "unable to decode " & $E & ": selector doesn't match"
  when compiles(E.arguments):
    without arguments =? E.decodeArguments(data), error:
      return failure "unable to decode " & $E & ": " & error.msg
    let message = "EVM reverted: " & $E & $arguments
    success (ref E)(msg: message, arguments: arguments)
  else:
    if data.len > 4:
      return failure "unable to decode " & $E & ": unread trailing bytes found"
    let message = "EVM reverted: " & $E & "()"
    success (ref E)(msg: message)

func encode*[E: SolidityError](_: type AbiEncoder, error: ref E): seq[byte] =
  result = @(E.selector.toArray)
  when compiles(error.arguments):
    result &= AbiEncoder.encode(error.arguments)

template convertCustomErrors*[ErrorTypes: tuple](body: untyped): untyped =
  try:
    body
  except ProviderError as error:
    block:
      if data =? error.data:
        for e in ErrorTypes.default.fields:
          if error =? typeof(e).decode(data):
            raise error
      raise error
