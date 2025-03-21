import pkg/serde
import std/macros
import std/sequtils
import pkg/chronicles
import pkg/chronos
import pkg/questionable
import pkg/contractabi
import ./basics
import ./provider
import ./signer
import ./events
import ./errors
import ./errors/conversion
import ./fields

export basics
export provider
export events
export errors.SolidityError
export errors.errors

{.push raises: [].}

logScope:
  topics = "ethers contract"

type
  Contract* = ref object of RootObj
    provider: Provider
    signer: ?Signer
    address: Address
  TransactionOverrides* = ref object of RootObj
    nonce*: ?UInt256
    chainId*: ?UInt256
    gasPrice*: ?UInt256
    maxFee*: ?UInt256
    maxPriorityFee*: ?UInt256
    gasLimit*: ?UInt256
  CallOverrides* = ref object of TransactionOverrides
    blockTag*: ?BlockTag
  Confirmable* = object
    response*: ?TransactionResponse
    convert*: ConvertCustomErrors
  EventHandler*[E: Event] = proc(event: ?!E) {.gcsafe, raises:[].}

func new*(ContractType: type Contract,
          address: Address,
          provider: Provider): ContractType =
  ContractType(provider: provider, address: address)

func new*(ContractType: type Contract,
          address: Address,
          signer: Signer): ContractType {.raises: [SignerError].} =
  ContractType(signer: some signer, provider: signer.provider, address: address)

func connect*[T: Contract](contract: T, provider: Provider | Signer): T {.raises: [SignerError].} =
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
                       overrides = TransactionOverrides()): Transaction =
  let selector = selector(function, typeof parameters).toArray
  let data = @selector & AbiEncoder.encode(parameters)
  Transaction(
    to: contract.address,
    data: data,
    nonce: overrides.nonce,
    chainId: overrides.chainId,
    gasPrice: overrides.gasPrice,
    maxFee: overrides.maxFee,
    maxPriorityFee: overrides.maxPriorityFee,
    gasLimit: overrides.gasLimit,
  )

proc decodeResponse(T: type, bytes: seq[byte]): T {.raises: [ContractError].} =
  without decoded =? AbiDecoder.decode(bytes, T):
    raiseContractError "unable to decode return value as " & $T
  return decoded

proc call(
    provider: Provider, transaction: Transaction, overrides: TransactionOverrides
): Future[seq[byte]] {.async: (raises: [ProviderError, CancelledError]).} =
  if overrides of CallOverrides and blockTag =? CallOverrides(overrides).blockTag:
    await provider.call(transaction, blockTag)
  else:
    await provider.call(transaction)

proc call(
    contract: Contract,
    function: string,
    parameters: tuple,
    overrides = TransactionOverrides(),
) {.async: (raises: [ProviderError, SignerError, CancelledError]).} =
  var transaction = createTransaction(contract, function, parameters, overrides)

  if signer =? contract.signer and transaction.sender.isNone:
    transaction.sender = some(await signer.getAddress())

  discard await contract.provider.call(transaction, overrides)

proc call(
    contract: Contract,
    function: string,
    parameters: tuple,
    ReturnType: type,
    overrides = TransactionOverrides(),
): Future[ReturnType] {.
    async: (raises: [ProviderError, SignerError, ContractError, CancelledError])
.} =
  var transaction = createTransaction(contract, function, parameters, overrides)

  if signer =? contract.signer and transaction.sender.isNone:
    transaction.sender = some(await signer.getAddress())

  let response = await contract.provider.call(transaction, overrides)
  return decodeResponse(ReturnType, response)

proc send(
  contract: Contract,
  function: string,
  parameters: tuple,
  overrides = TransactionOverrides()
): Future[?TransactionResponse] {.async: (raises: [SignerError, ProviderError, CancelledError]).} =

  if signer =? contract.signer:
    withLock(signer):
      let transaction = createTransaction(contract, function, parameters, overrides)
      let populated = await signer.populateTransaction(transaction)
      trace "sending contract transaction", function, params = $parameters
      let txResp = await signer.sendTransaction(populated)
      return txResp.some
  else:
    await call(contract, function, parameters, overrides)
    return TransactionResponse.none

func getParameterTuple(procedure: NimNode): NimNode =
  let parameters = procedure[3]
  var tupl = newNimNode(nnkTupleConstr, parameters)
  for parameter in parameters[2..^1]:
    for name in parameter[0..^3]:
      tupl.add name
  return tupl

func getErrorTypes(procedure: NimNode): NimNode =
  let pragmas = procedure[4]
  var tupl = newNimNode(nnkTupleConstr)
  for pragma in pragmas:
    if pragma.kind == nnkExprColonExpr:
      if pragma[0].eqIdent "errors":
        pragma[1].expectKind(nnkBracket)
        for error in pragma[1]:
          tupl.add error
  if tupl.len == 0:
    quote do: tuple[]
  else:
    tupl

func isGetter(procedure: NimNode): bool =
  let pragmas = procedure[4]
  for pragma in pragmas:
    if pragma.eqIdent "getter":
      return true
  false

func isConstant(procedure: NimNode): bool =
  let pragmas = procedure[4]
  for pragma in pragmas:
    if pragma.eqIdent "view":
      return true
    elif pragma.eqIdent "pure":
      return true
    elif pragma.eqIdent "getter":
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
      quote do: TransactionOverrides()
    )
  )

func addContractCall(procedure: var NimNode) =
  let contract = procedure[3][1][0]
  let function = $basename(procedure[0])
  let parameters = getParameterTuple(procedure)
  let returnType = procedure[3][0]
  let isGetter = procedure.isGetter

  procedure.addOverrides()
  let errors = getErrorTypes(procedure)

  func call: NimNode =
    if returnType.kind == nnkEmpty:
      quote:
        await call(`contract`, `function`, `parameters`, overrides)
    elif returnType.isMultipleReturn or isGetter:
      quote:
        return await call(
          `contract`, `function`, `parameters`, `returnType`, overrides
        )
    else:
      quote:
        # solidity functions return a tuple, so wrap return type in a tuple
        let tupl = await call(
          `contract`, `function`, `parameters`, (`returnType`,), overrides
        )
        return tupl[0]

  func send: NimNode =
    if returnType.kind == nnkEmpty:
      quote:
        discard await send(`contract`, `function`, `parameters`, overrides)
    else:
      quote:
        when typeof(result) isnot Confirmable:
          {.error:
            "unexpected return type, " &
            "missing {.view.}, {.pure.} or {.getter.} ?"
          .}
        let response = await send(`contract`, `function`, `parameters`, overrides)
        let convert = customErrorConversion(`errors`)
        Confirmable(response: response, convert: convert)

  procedure[6] =
    if procedure.isConstant:
      call()
    else:
      send()

func addErrorHandling(procedure: var NimNode) =
  let body = procedure[6]
  let errors = getErrorTypes(procedure)
  procedure[6] = quote do:
    try:
      `body`
    except ProviderError as error:
      if data =? error.data:
        let convert = customErrorConversion(`errors`)
        raise convert(error)
      else:
        raise error

func addFuture(procedure: var NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind != nnkEmpty:
    procedure[3][0] = quote: Future[`returntype`]

func addAsyncPragma(procedure: var NimNode) =
  let pragmas = procedure[4]
  if pragmas.kind == nnkEmpty:
    procedure[4] = newNimNode(nnkPragma)
  procedure[4].add nnkExprColonExpr.newTree(
    newIdentNode("async"),
    nnkTupleConstr.newTree(
      nnkExprColonExpr.newTree(
        newIdentNode("raises"),
        nnkBracket.newTree(
          newIdentNode("CancelledError"),
          newIdentNode("ProviderError"),
          newIdentNode("EthersError"),
        ),
      )
    ),
  )

macro contract*(procedure: untyped{nkProcDef | nkMethodDef}): untyped =
  let parameters = procedure[3]
  let body = procedure[6]

  parameters.expectMinLen(2) # at least return type and contract instance
  body.expectKind(nnkEmpty)

  var contractcall = copyNimTree(procedure)
  contractcall.addContractCall()
  contractcall.addErrorHandling()
  contractcall.addFuture()
  contractcall.addAsyncPragma()
  contractcall

template view* {.pragma.}
template pure* {.pragma.}
template getter* {.pragma.}

proc subscribe*[E: Event](contract: Contract,
                          _: type E,
                          handler: EventHandler[E]):
                         Future[Subscription] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = EventFilter(address: contract.address, topics: @[topic])

  proc logHandler(logResult: ?!Log) {.raises: [].} =
    without log =? logResult, error:
      handler(failure(E, error))
      return

    if event =? E.decode(log.data, log.topics):
      handler(success(event))

  contract.provider.subscribe(filter, logHandler)

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

proc queryFilter[E: Event](contract: Contract,
                            _: type E,
                            filter: EventFilter):
                           Future[seq[E]] {.async.} =

  var logs = await contract.provider.getLogs(filter)
  logs.keepItIf(not it.removed)

  var events: seq[E] = @[]
  for log in logs:
    if event =? E.decode(log.data, log.topics):
      events.add event

  return events

proc queryFilter*[E: Event](contract: Contract,
                            _: type E):
                           Future[seq[E]] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = EventFilter(address: contract.address,
                           topics: @[topic])

  contract.queryFilter(E, filter)

proc queryFilter*[E: Event](contract: Contract,
                            _: type E,
                            blockHash: BlockHash):
                           Future[seq[E]] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = FilterByBlockHash(address: contract.address,
                                 topics: @[topic],
                                 blockHash: blockHash)

  contract.queryFilter(E, filter)

proc queryFilter*[E: Event](contract: Contract,
                            _: type E,
                            fromBlock: BlockTag,
                            toBlock: BlockTag):
                           Future[seq[E]] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = Filter(address: contract.address,
                      topics: @[topic],
                      fromBlock: fromBlock,
                      toBlock: toBlock)

  contract.queryFilter(E, filter)
