import std/json
import std/strutils
import pkg/ethers

proc revertReason*(e: ref EthersError): string =
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

template reverts*(body: untyped): untyped =
  let asyncproc = proc(): Future[bool] {.async.} =
    try:
      body
      return false
    except EthersError:
      return true
    except CatchableError:
      return false
  waitFor asyncproc()

template revertsWith*(reason: string, body: untyped): untyped =
  let asyncproc = proc(): Future[bool] {.async.} =
    try:
      body
      return false
    except EthersError as e:
      return reason == revertReason(e)
    except CatchableError as e:
      return false
  waitFor asyncproc()

template doesNotRevert*(body: untyped): untyped =
  let asyncproc = proc(): Future[bool] {.async.} =
    return not reverts(body)
  waitFor asyncproc()

template doesNotRevertWith*(reason: string, body: untyped): untyped =
  let asyncproc = proc(): Future[bool] {.async.} =
    return not revertsWith(reason, body)
  waitFor asyncproc()