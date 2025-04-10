import ../provider
import ./errors/conversion

{.push raises: [].}

type Confirmable* = object
  response*: ?TransactionResponse
  convert*: ConvertCustomErrors

proc confirm(tx: Confirmable, confirmations, timeout: int):
  Future[TransactionReceipt] {.async: (raises: [CancelledError, EthersError]).} =

  without response =? tx.response:
    raise newException(
      EthersError,
      "Transaction hash required. Possibly was a call instead of a send?"
    )

  try:
    return await response.confirm(confirmations, timeout)
  except ProviderError as error:
    let convert = tx.convert
    raise convert(error)

proc confirm*(tx: Future[Confirmable],
              confirmations: int = EthersDefaultConfirmations,
              timeout: int = EthersReceiptTimeoutBlks):
             Future[TransactionReceipt] {.async: (raises: [CancelledError, EthersError]).} =
  ## Convenience method that allows confirm to be chained to a contract
  ## transaction, eg:
  ## `await token.connect(signer0)
  ##          .mint(accounts[1], 100.u256)
  ##          .confirm(3)`
  try:
    return await (await tx).confirm(confirmations, timeout)
  except CancelledError as e:
    raise e
  except EthersError as e:
    raise e
  except CatchableError as e:
    raise newException(
      EthersError,
      "Error when trying to confirm the contract transaction: " & e.msg
    )

