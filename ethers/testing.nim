import std/strutils
import ./provider
import ./signer

proc revertReason*(e: ref EthersError): string =
  var msg = e.msg
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

proc reverts*[T](call: Future[T]): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call
    return false
  except ProviderError, SignerError:
    return true

proc reverts*[T](call: Future[T], reason: string): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call
    return false
  except EthersError as error:
    var passed = reason == error.revertReason
    if not passed and
       not error.parent.isNil and
       error.parent of (ref EthersError):
      let revertReason = (ref EthersError)(error.parent).revertReason
      passed = reason == revertReason
    return passed
