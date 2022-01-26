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

func new*(ContractType: type Contract,
          address: Address,
          provider: Provider): ContractType =
  ContractType(provider: provider, address: address)

func new*(ContractType: type Contract,
          address: Address,
          signer: Signer): ContractType =
  ContractType(signer: some signer, provider: signer.provider, address: address)

func connect*[T: Contract](contract: T, provider: Provider | Signer): T =
  T.new(contract.address, provider)

func provider*(contract: Contract): Provider =
  contract.provider

func signer*(contract: Contract): ?Signer =
  contract.signer

func address*(contract: Contract): Address =
  contract.address

template raiseContractError(message: string) =
  raise newException(ContractError, message)

proc createTransaction(contract: Contract,
                       function: string,
                       parameters: tuple): Transaction =
  let selector = selector(function, typeof parameters).toArray
  let data = @selector & AbiEncoder.encode(parameters)
  Transaction(to: contract.address, data: data)

proc decodeResponse(T: type, bytes: seq[byte]): T =
  without decoded =? AbiDecoder.decode(bytes, T):
    raiseContractError "unable to decode return value as " & $T
  return decoded

proc call(contract: Contract, function: string, parameters: tuple) {.async.} =
  let transaction = createTransaction(contract, function, parameters)
  discard await contract.provider.call(transaction)

proc call(contract: Contract,
          function: string,
          parameters: tuple,
          ReturnType: type): Future[ReturnType] {.async.} =
  let transaction = createTransaction(contract, function, parameters)
  let response = await contract.provider.call(transaction)
  return decodeResponse(ReturnType, response)

proc send(contract: Contract, function: string, parameters: tuple) {.async.} =
  if signer =? contract.signer:
    let transaction = createTransaction(contract, function, parameters)
    let populated = await signer.populateTransaction(transaction)
    await signer.sendTransaction(populated)
  else:
    await call(contract, function, parameters)

func getParameterTuple(procedure: NimNode): NimNode =
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
  let contract = procedure[3][1][0]
  let function = $basename(procedure[0])
  let parameters = getParameterTuple(procedure)
  let returntype = procedure[3][0]
  procedure[6] =
    if procedure.isConstant:
      if returntype.kind == nnkEmpty:
        quote:
          await call(`contract`, `function`, `parameters`)
      else:
        quote:
          return await call(`contract`, `function`, `parameters`, `returntype`)
    else:
      quote:
        await send(`contract`, `function`, `parameters`)

func addFuture(procedure: var NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind != nnkEmpty:
    procedure[3][0] = quote: Future[`returntype`]

func addAsyncPragma(procedure: var NimNode) =
  let pragmas = procedure[4]
  if pragmas.kind == nnkEmpty:
    procedure[4] = newNimNode(nnkPragma)
  procedure[4].add ident("async")

func checkReturnType(procedure: NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind != nnkEmpty and not procedure.isConstant:
    const message =
      "only contract functions with {.constant.}, {.pure.} or {.view.} " &
      "can have a return type"
    error(message, returntype)

macro contract*(procedure: untyped{nkProcDef|nkMethodDef}): untyped =

  let parameters = procedure[3]
  let body = procedure[6]

  parameters.expectMinLen(2) # at least return type and contract instance
  body.expectKind(nnkEmpty)
  procedure.checkReturnType()

  var contractcall = copyNimTree(procedure)
  contractcall.addContractCall()
  contractcall.addFuture()
  contractcall.addAsyncPragma()
  contractcall

template view* {.pragma.}
template pure* {.pragma.}
template constant* {.pragma.}
