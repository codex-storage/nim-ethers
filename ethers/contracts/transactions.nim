import pkg/contractabi
import pkg/chronicles
import ../basics
import ../provider
import ../signer
import ../transaction
import ./contract
import ./contractcall
import ./overrides

{.push raises: [].}

logScope:
  topics = "ethers contract"

proc createTransaction*(call: ContractCall): Transaction =
  let selector = selector(call.function, typeof call.arguments).toArray
  let data = @selector & AbiEncoder.encode(call.arguments)
  Transaction(
    to: call.contract.address,
    data: data,
    nonce: call.overrides.nonce,
    chainId: call.overrides.chainId,
    gasPrice: call.overrides.gasPrice,
    maxFeePerGas: call.overrides.maxFeePerGas,
    maxPriorityFeePerGas: call.overrides.maxPriorityFeePerGas,
    gasLimit: call.overrides.gasLimit,
  )

proc decodeResponse(T: type, bytes: seq[byte]): T {.raises: [ContractError].} =
  without decoded =? AbiDecoder.decode(bytes, T):
    raise newException(ContractError, "unable to decode return value as " & $T)
  return decoded

proc call(
    provider: Provider, transaction: Transaction, overrides: TransactionOverrides
): Future[seq[byte]] {.async: (raises: [ProviderError, CancelledError]).} =
  if overrides of CallOverrides and blockTag =? CallOverrides(overrides).blockTag:
    await provider.call(transaction, blockTag)
  else:
    await provider.call(transaction)

proc callTransaction*(call: ContractCall) {.async: (raises: [ProviderError, SignerError, CancelledError]).} =
  var transaction = createTransaction(call)

  if signer =? call.contract.signer and transaction.sender.isNone:
    transaction.sender = some(await signer.getAddress())

  discard await call.contract.provider.call(transaction, call.overrides)

proc callTransaction*(call: ContractCall, ReturnType: type): Future[ReturnType] {.async: (raises: [ProviderError, SignerError, ContractError, CancelledError]).} =
  var transaction = createTransaction(call)

  if signer =? call.contract.signer and transaction.sender.isNone:
    transaction.sender = some(await signer.getAddress())

  let response = await call.contract.provider.call(transaction, call.overrides)
  return decodeResponse(ReturnType, response)

proc sendTransaction*(call: ContractCall): Future[?TransactionResponse] {.async: (raises: [SignerError, ProviderError, CancelledError]).} =
  if signer =? call.contract.signer:
    withLock(signer):
      let transaction = createTransaction(call)
      let populated = await signer.populateTransaction(transaction)
      trace "sending contract transaction", function = call.function, params = $call.arguments
      let txResp = await signer.sendTransaction(populated)
      return txResp.some
  else:
    await callTransaction(call)
    return TransactionResponse.none

