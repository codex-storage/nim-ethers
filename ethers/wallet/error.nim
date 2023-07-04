import ../basics

type
  WalletError* = object of EthersError

func raiseWalletError*(message: string) =
  raise newException(WalletError, message)
