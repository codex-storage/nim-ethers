import ../basics
import ./contract
import ./overrides

type ContractCall*[Arguments: tuple] = object
  contract: Contract
  function: string
  arguments: Arguments
  overrides: TransactionOverrides

func init*[Arguments: tuple](
  _: type ContractCall,
  contract: Contract,
  function: string,
  arguments: Arguments,
  overrides: TransactionOverrides
): ContractCall[arguments] =
  ContractCall[Arguments](
    contract: contract,
    function: function,
    arguments: arguments,
    overrides: overrides
  )

func contract*(call: ContractCall): Contract =
  call.contract

func function*(call: ContractCall): string =
  call.function

func arguments*(call: ContractCall): auto =
  call.arguments

func overrides*(call: ContractCall): TransactionOverrides =
  call.overrides
