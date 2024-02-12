import std/strutils
import ./provider
import ./signer

proc revertReason*(emsg: string): string =
  var msg = emsg
  const revertPrefixes = @[
    # hardhat
    "Error: VM Exception while processing transaction: reverted with " &
    "reason string ",
    # ganache
    "VM Exception while processing transaction: revert "
  ]
  for prefix in revertPrefixes.items:
    msg = msg.replace(prefix)
  msg = msg.replace("\'")
  return msg

proc revertReason*(e: ref EthersError): string =
  var msg = e.msg
  msg.revertReason

proc reverts*[T](call: Future[T]): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call
    return false
  except ProviderError, SignerError, EstimateGasError:
    return true

proc reverts*[T](call: Future[T], reason: string): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call
    return false
  except ProviderError, SignerError, EstimateGasError:
    let e = getCurrentException()
    var passed = reason == (ref EthersError)(e).revertReason
    if not passed and
       not e.parent.isNil and
       e.parent of (ref EthersError):
      let revertReason = (ref EthersError)(e.parent).revertReason
      passed = reason == revertReason
    return passed
