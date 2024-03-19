import pkg/contractabi/selector
import ./basics

type SolidityError* = object of EthersError

{.push raises:[].}

template errors*(types) {.pragma.}

func decode*[E: SolidityError](_: type E, data: seq[byte]): ?!(ref E) =
  const name = $E
  const selector = selector(name, typeof(()))
  if data.len < 4:
    return failure "unable to decode " & name & ": signature too short"
  if selector.toArray[0..<4] != data[0..<4]:
    return failure "unable to decode " & name & ": signature doesn't match"
  success (ref E)()
