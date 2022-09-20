import std/strutils
import std/json
import ./provider

proc revertReason*(e: ref ProviderError): string =
  try:
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
  except JsonParsingError:
    return ""

proc reverts*[T](call: Future[T]): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call
    return false
  except ProviderError:
    return true

proc reverts*[T](call: Future[T], reason: string): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call
    return false
  except ProviderError as error:
    return reason == error.revertReason
