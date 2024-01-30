import ../../signer

type
  WalletError* = object of SignerError

func raiseWalletError*(message: string) {.raises: [WalletError].}=
  raise newException(WalletError, message)

template convertError*(body) =
  try:
    body
  except CatchableError as error:
    raiseWalletError(error.msg)
