import ./basics

type
  SolidityError* = object of EthersError
  ContractError* = object of EthersError
  SignerError* = object of EthersError
  SubscriptionError* = object of EthersError
  SubscriptionResult*[E] = Result[E, ref SubscriptionError]
  ProviderError* = object of EthersError
    data*: ?seq[byte]

template raiseSignerError*(message: string, parent: ref ProviderError = nil) =
  raise newException(SignerError, message, parent)

{.push raises:[].}

template errors*(types) {.pragma.}
