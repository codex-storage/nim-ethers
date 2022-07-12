import std/macros
import pkg/chronos
import pkg/contractabi
import ./basics
import ./provider
import ./signer
import ./events
import ./fields

export basics
export provider
export events

type
  Contract* = ref object of RootObj
    provider: Provider
    signer: ?Signer
    address: Address
  TransactionOverrides* = object
    nonce*: ?UInt256
    gasPrice*: ?UInt256
    gasLimit*: ?UInt256

  ContractError* = object of EthersError
  Confirmable* = ?TransactionResponse
  EventHandler*[E: Event] = proc(event: E) {.gcsafe, upraises:[].}

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
                       parameters: tuple,
                       overrides = TransactionOverrides.default): Transaction =
  let selector = selector(function, typeof parameters).toArray
  let data = @selector & AbiEncoder.encode(parameters)
  Transaction(
    to: contract.address,
    data: data,
    gasPrice: overrides.gasPrice,
    gasLimit: overrides.gasLimit,
    nonce: overrides.nonce
  )

proc decodeResponse(T: type, multiple: static bool, bytes: seq[byte]): T =
  when multiple:
    without decoded =? AbiDecoder.decode(bytes, T):
      raiseContractError "unable to decode return value as " & $T
    return decoded
  else:
    return decodeResponse((T,), true, bytes)[0]

proc call(contract: Contract,
          function: string,
          parameters: tuple,
          blockTag = BlockTag.latest) {.async.} =
  let transaction = createTransaction(contract, function, parameters)
  discard await contract.provider.call(transaction, blockTag)

proc call(contract: Contract,
          function: string,
          parameters: tuple,
          ReturnType: type,
          returnMultiple: static bool,
          blockTag = BlockTag.latest): Future[ReturnType] {.async.} =
  let transaction = createTransaction(contract, function, parameters)
  let response = await contract.provider.call(transaction, blockTag)
  return decodeResponse(ReturnType, returnMultiple, response)

proc send(contract: Contract,
          function: string,
          parameters: tuple,
          overrides = TransactionOverrides.default):
         Future[?TransactionResponse] {.async.} =
  if signer =? contract.signer:
    let transaction = createTransaction(contract, function, parameters, overrides)
    let populated = await signer.populateTransaction(transaction)
    let txResp = await signer.sendTransaction(populated)
    return txResp.some
  else:
    await call(contract, function, parameters)
    return TransactionResponse.none

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
  false

func isMultipleReturn(returnType: NimNode): bool =
  (returnType.kind == nnkPar and returnType.len > 1) or
  (returnType.kind == nnkTupleConstr) or
  (returnType.kind == nnkTupleTy)

func addOverrides(procedure: var NimNode) =
  procedure[3].add(
    newIdentDefs(
      ident("overrides"),
      newEmptyNode(),
      quote do: TransactionOverrides.default
    )
  )

func addContractCall(procedure: var NimNode) =
  let contract = procedure[3][1][0]
  let function = $basename(procedure[0])
  let parameters = getParameterTuple(procedure)
  let returnType = procedure[3][0]
  let returnMultiple = returnType.isMultipleReturn.newLit

  procedure.addOverrides()

  func call: NimNode =
    if returnType.kind == nnkEmpty:
      quote:
        await call(`contract`, `function`, `parameters`)
    else:
      quote:
        return await call(
          `contract`, `function`, `parameters`, `returnType`, `returnMultiple`)

  func send: NimNode =
    if returnType.kind == nnkEmpty:
      quote:
        discard await send(`contract`, `function`, `parameters`, overrides)
    else:
      quote:
        when typeof(result) isnot Confirmable:
          {.error: "unexpected return type, missing {.view.} or {.pure.} ?".}
        return await send(`contract`, `function`, `parameters`, overrides)

  procedure[6] =
    if procedure.isConstant:
      call()
    else:
      send()

func addFuture(procedure: var NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind != nnkEmpty:
    procedure[3][0] = quote: Future[`returntype`]

func addAsyncPragma(procedure: var NimNode) =
  let pragmas = procedure[4]
  if pragmas.kind == nnkEmpty:
    procedure[4] = newNimNode(nnkPragma)
  procedure[4].add ident("async")

macro contract*(procedure: untyped{nkProcDef|nkMethodDef}): untyped =

  let parameters = procedure[3]
  let body = procedure[6]

  parameters.expectMinLen(2) # at least return type and contract instance
  body.expectKind(nnkEmpty)

  var contractcall = copyNimTree(procedure)
  contractcall.addContractCall()
  contractcall.addFuture()
  contractcall.addAsyncPragma()
  contractcall

template view* {.pragma.}
template pure* {.pragma.}

proc subscribe*[E: Event](contract: Contract,
                          _: type E,
                          handler: EventHandler[E]):
                         Future[Subscription] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = Filter(address: contract.address, topics: @[topic])

  proc logHandler(log: Log) {.upraises: [].} =
    if event =? E.decode(log.data, log.topics):
      handler(event)

  contract.provider.subscribe(filter, logHandler)
