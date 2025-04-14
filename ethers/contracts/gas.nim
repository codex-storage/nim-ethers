import std/macros
import ../basics
import ../provider
import ../signer
import ./contract
import ./contractcall
import ./transactions
import ./overrides
import ./errors
import ./syntax

type ContractGasEstimations[C] = distinct C

func estimateGas*[C: Contract](contract: C): ContractGasEstimations[C] =
  ContractGasEstimations[C](contract)

proc estimateGas(
  call: ContractCall
): Future[UInt256] {.async: (raises: [CancelledError, ProviderError, EthersError]).} =
  let transaction = createTransaction(call)
  var blockTag = BlockTag.pending
  if call.overrides of CallOverrides:
    if tag =? CallOverrides(call.overrides).blockTag:
      blockTag = tag
  if signer =? call.contract.signer:
    await signer.estimateGas(transaction, blockTag)
  else:
    await call.contract.provider.estimateGas(transaction, blockTag)

func wrapFirstParameter(procedure: var NimNode) =
  let contractType = procedure.params[1][1]
  let gasEstimationsType = quote do: ContractGasEstimations[`contractType`]
  procedure.params[1][1] = gasEstimationsType

func setReturnType(procedure: var NimNode) =
  procedure.params[0] = quote do: Future[UInt256]

func addEstimateCall(procedure: var NimNode) =
  let contractCall = getContractCall(procedure)
  procedure.body = quote do:
    return await estimateGas(`contractCall`)

func createGasEstimationCall*(procedure: NimNode): NimNode =
  result = copyNimTree(procedure)
  result.wrapFirstParameter()
  result.addOverridesParameter()
  result.setReturnType()
  result.addAsyncPragma()
  result.addUsedPragma()
  result.addEstimateCall()
  result.addErrorHandling()
