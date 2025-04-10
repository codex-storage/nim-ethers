import std/macros
import ./errors/conversion

func getErrorTypes*(procedure: NimNode): NimNode =
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

func addErrorHandling*(procedure: var NimNode) =
  let body = procedure[6]
  let errors = getErrorTypes(procedure)
  procedure.body = quote do:
    try:
      `body`
    except ProviderError as error:
      if data =? error.data:
        let convert = customErrorConversion(`errors`)
        raise convert(error)
      else:
        raise error
