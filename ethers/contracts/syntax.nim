import std/macros
import ./contractcall

template view* {.pragma.}
template pure* {.pragma.}
template getter* {.pragma.}
template errors*(types) {.pragma.}

func isGetter*(procedure: NimNode): bool =
  let pragmas = procedure[4]
  for pragma in pragmas:
    if pragma.eqIdent "getter":
      return true
  false

func isConstant*(procedure: NimNode): bool =
  let pragmas = procedure[4]
  for pragma in pragmas:
    if pragma.eqIdent "view":
      return true
    elif pragma.eqIdent "pure":
      return true
    elif pragma.eqIdent "getter":
      return true
  false

func isMultipleReturn*(returnType: NimNode): bool =
  (returnType.kind == nnkPar and returnType.len > 1) or
  (returnType.kind == nnkTupleConstr) or
  (returnType.kind == nnkTupleTy)

func getContract(procedure: NimNode): NimNode =
  let firstArgument = procedure.params[1][0]
  quote do:
    Contract(`firstArgument`)

func getFunctionName(procedure: NimNode): string =
  $basename(procedure[0])

func getArgumentTuple(procedure: NimNode): NimNode =
  let parameters = procedure.params
  var arguments = newNimNode(nnkTupleConstr, parameters)
  for parameter in parameters[2..^2]:
    for name in parameter[0..^3]:
      arguments.add name
  return arguments

func getOverrides(procedure: NimNode): NimNode =
  procedure.params.last[^3]

func getContractCall*(procedure: NimNode): NimNode =
  let contract = getContract(procedure)
  let function = getFunctionName(procedure)
  let arguments = getArgumentTuple(procedure)
  let overrides = getOverrides(procedure)
  quote do:
    ContractCall.init(`contract`, `function`, `arguments`, `overrides`)

func addOverridesParameter*(procedure: var NimNode) =
  let overrides = genSym(nskParam, "overrides")
  procedure.params.add(
    newIdentDefs(
      overrides,
      newEmptyNode(),
      quote do: TransactionOverrides()
    )
  )

func addAsyncPragma*(procedure: var NimNode) =
  procedure.addPragma nnkExprColonExpr.newTree(
    quote do: async,
    quote do: (raises: [CancelledError, ProviderError, EthersError])
  )

func addUsedPragma*(procedure: var NimNode) =
  procedure.addPragma(quote do: used)
