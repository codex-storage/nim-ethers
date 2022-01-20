import std/macros
import pkg/chronos
import pkg/contractabi
import ./basics
import ./provider

export basics
export provider

type
  Contract* = ref object of RootObj
    provider: Provider
    address: Address
  ContractError* = object of IOError

template raiseContractError(message: string) =
  raise newException(ContractError, message)

proc createTxData(function: string, parameters: tuple): seq[byte] =
  let selector = selector(function, typeof parameters).toArray
  return @selector & AbiEncoder.encode(parameters)

proc createTx(contract: Contract,
              function: string,
              parameters: tuple): Transaction =
  Transaction(to: contract.address, data: createTxData(function, parameters))

proc decodeResponse(T: type, bytes: seq[byte]): T =
  without decoded =? AbiDecoder.decode(bytes, T):
    raiseContractError "unable to decode return value as " & $T
  return decoded

proc call[ContractType: Contract, ResultType](
          contract: ContractType,
          function: string,
          parameters: tuple):Future[ResultType] {.async.} =
  let transaction = createTx(contract, function, parameters)
  let response = await contract.provider.call(transaction)
  return decodeResponse(ResultType, response)

func getParameterTuple(procedure: var NimNode): NimNode =
  let parameters = procedure[3]
  var tupl = newNimNode(nnkTupleConstr, parameters)
  for parameter in parameters[2..^1]:
    for name in parameter[0..^3]:
      tupl.add name
  return tupl

func addContractCall(procedure: var NimNode) =
  let name = procedure[0]
  let function = if name.kind == nnkPostfix: $name[1] else: $name
  let parameters = procedure[3]
  let contract = parameters[1][0]
  let contracttype = parameters[1][1]
  let resulttype = parameters[0]
  let tupl = getParameterTuple(procedure)
  procedure[6] = quote do:
    return await call[`contracttype`,`resulttype`](`contract`, `function`, `tupl`)

func addFuture(procedure: var NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind == nnkEmpty:
    procedure[3][0] = quote do: Future[void]
  else:
    procedure[3][0] = quote do: Future[`returntype`]

func addAsyncPragma(procedure: var NimNode) =
  let pragmas = procedure[4]
  if pragmas.kind == nnkEmpty:
    procedure[4] = newNimNode(nnkPragma)
  procedure[4].add ident("async")

func new*(ContractType: type Contract,
          address: Address,
          provider: Provider): ContractType =
  ContractType(provider: provider, address: address)

macro contract*(procedure: untyped{nkProcDef|nkMethodDef}): untyped =
  let parameters = procedure[3]
  let body = procedure[6]
  parameters.expectMinLen(2)
  body.expectKind(nnkEmpty)
  var contractcall = copyNimTree(procedure)
  contractcall.addContractCall()
  contractcall.addFuture()
  contractcall.addAsyncPragma()
  contractcall
