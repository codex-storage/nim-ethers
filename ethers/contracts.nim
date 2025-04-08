import std/macros
import ./contracts/contract
import ./contracts/overrides
import ./contracts/confirmation
import ./contracts/events
import ./contracts/filters
import ./contracts/syntax
import ./contracts/function

export contract
export overrides
export confirmation
export events
export filters
export syntax.view
export syntax.pure
export syntax.getter
export syntax.errors

{.push raises: [].}

macro contract*(procedure: untyped{nkProcDef | nkMethodDef}): untyped =
  procedure.params.expectMinLen(2) # at least return type and contract instance
  procedure.body.expectKind(nnkEmpty)

  createContractFunction(procedure)
