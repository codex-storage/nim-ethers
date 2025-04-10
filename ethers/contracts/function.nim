import std/macros
import ./errors/conversion
import ./syntax
import ./transactions
import ./errors

func addContractCall(procedure: var NimNode) =
  let contractCall = getContractCall(procedure)
  let returnType = procedure.params[0]
  let isGetter = procedure.isGetter

  let errors = getErrorTypes(procedure)

  func call: NimNode =
    if returnType.kind == nnkEmpty:
      quote:
        await callTransaction(`contractCall`)
    elif returnType.isMultipleReturn or isGetter:
      quote:
        return await callTransaction(`contractCall`, `returnType`)
    else:
      quote:
        # solidity functions return a tuple, so wrap return type in a tuple
        let tupl = await callTransaction(`contractCall`, (`returnType`,))
        return tupl[0]

  func send: NimNode =
    if returnType.kind == nnkEmpty:
      quote:
        discard await sendTransaction(`contractCall`)
    else:
      quote:
        when typeof(result) isnot Confirmable:
          {.error:
            "unexpected return type, " &
            "missing {.view.}, {.pure.} or {.getter.} ?"
          .}
        let response = await sendTransaction(`contractCall`)
        let convert = customErrorConversion(`errors`)
        Confirmable(response: response, convert: convert)

  procedure.body =
    if procedure.isConstant:
      call()
    else:
      send()

func addFuture(procedure: var NimNode) =
  let returntype = procedure[3][0]
  if returntype.kind != nnkEmpty:
    procedure[3][0] = quote: Future[`returntype`]

func createContractFunction*(procedure: NimNode): NimNode =
  result = copyNimTree(procedure)
  result.addOverridesParameter()
  result.addContractCall()
  result.addErrorHandling()
  result.addFuture()
  result.addAsyncPragma()

