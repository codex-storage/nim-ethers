import std/json
import std/strutils
import pkg/ethers

proc revertReason*(e: ref JsonRpcProviderError): string =
  try:
    let json = parseJson(e.msg)
    var msg = json{"message"}.getStr
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
      discard await call # TODO test this
    return false
  except JsonRpcProviderError:
    return true # TODO: check that error started with revert prefix

proc reverts*[T](call: Future[T], reason: string): Future[bool] {.async.} =
  try:
    when T is void:
      await call
    else:
      discard await call # TODO test this
    return false
  except JsonRpcProviderError as error:
    return reason == error.revertReason
