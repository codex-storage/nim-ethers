import ./basics

type
  SolidityError* = object of EthersError
  ContractError* = object of EthersError
  SignerError* = object of EthersError
  ProviderError* = object of EthersError
    data*: ?seq[byte]

{.push raises:[].}

proc toErr*[E1: ref CatchableError, E2: EthersError](
  e1: E1,
  _: type E2,
  msg: string = e1.msg): ref E2 =

  return newException(E2, msg, e1)
