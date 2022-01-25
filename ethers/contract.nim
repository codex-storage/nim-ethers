import std/macros
import pkg/chronos
import pkg/contractabi
import ./basics
import ./provider
import ./signer

export basics
export provider

type
  Contract* = ref object of RootObj
    provider: Provider
    signer: ?Signer
    address: Address
  ContractError* = object of EthersError

func provider*(contract: Contract): Provider =
  contract.provider

func signer*(contract: Contract): ?Signer =
  contract.signer

func address*(contract: Contract): Address =
  contract.address

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

proc call[ContractType: Contract, ReturnType](
          contract: ContractType,
          function: string,
          parameters: tuple): Future[ReturnType] {.async.} =
  let transaction = createTx(contract, function, parameters)
  let response = await contract.provider.call(transaction)
  return decodeResponse(ReturnType, response)

proc callNoResult[ContractType: Contract](
                  contract: ContractType,
                  function: string,
                  parameters: tuple) {.async.} =
  let transaction = createTx(contract, function, parameters)
  discard await contract.provider.call(transaction)

proc send[ContractType: Contract](
          contract: ContractType,
          function: string,
          parameters: tuple) {.async.} =

  without signer =? contract.signer:
    raiseContractError "trying to send transaction without a signer"

  let transaction = createTx(contract, function, parameters)
  let populated = await signer.populateTransaction(transaction)
  await signer.sendTransaction(populated)

func getParameterTuple(procedure: var NimNode): NimNode =
  let parameters = procedure[3]
  var tupl = newNimNode(nnkTupleConstr, parameters)
  for parameter in parameters[2..^1]:
    for name in parameter[0..^3]:
      tupl.add name
  return tupl

func isConstant(procedure: NimNode): bool =
  let pragmas = procedure[4]
  for pragma in pragmas:
    if pragma.eqIdent "view":
      return true
    elif pragma.eqIdent "pure":
      return true
    elif pragma.eqIdent "constant":
      return true
  false

func addContractCall(procedure: var NimNode) =
  let name = procedure[0]
  let function = if name.kind == nnkPostfix: $name[1] else: $name
  let parameters = procedure[3]
  let contract = parameters[1][0]
  let contracttype = parameters[1][1]
  let returntype = parameters[0]
  let tupl = getParameterTuple(procedure)
  if procedure.isConstant:
    if returntype.kind == nnkEmpty:
      procedure[6] = quote do:
        await callNoResult[`contracttype`](
          `contract`, `function`, `tupl`
        )
    else:
      procedure[6] = quote do:
        return await call[`contracttype`,`returntype`](
          `contract`, `function`, `tupl`
        )
  else:
    procedure[6] = quote do:
      if `contract`.signer.isSome:
        await send[`contracttype`](`contract`, `function`, `tupl`)
      else:
        await callNoResult[`contracttype`](`contract`, `function`, `tupl`)

func addFuture(procedure: var NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind != nnkEmpty:
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

func new*(ContractType: type Contract,
          address: Address,
          signer: Signer): ContractType =
  ContractType(signer: some signer, provider: signer.provider, address: address)

template view* {.pragma.}
template pure* {.pragma.}
template constant* {.pragma.}

func checkReturnType(procedure: NimNode) =
  let parameters = procedure[3]
  let returntype = parameters[0]
  if returntype.kind != nnkEmpty and not procedure.isConstant:
    const message =
      "only contract functions with {.constant.}, {.pure.} or {.view.} " &
      "can have a return type"
    error(message, returntype)

macro contract*(procedure: untyped{nkProcDef|nkMethodDef}): untyped =
  let parameters = procedure[3]
  let body = procedure[6]
  parameters.expectMinLen(2)
  body.expectKind(nnkEmpty)
  procedure.checkReturnType()
  var contractcall = copyNimTree(procedure)
  contractcall.addContractCall()
  contractcall.addFuture()
  contractcall.addAsyncPragma()
  contractcall
