import ../basics

type
  WalletError* = object of EthersError

func raiseWalletError*(message: string) {.raises: [WalletError].}=
  raise newException(WalletError, message)
