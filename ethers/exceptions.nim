import ./basics

func msgStack*(error: ref EthersError): string =
  var msg = error.msg
  if not error.parent.isNil:
    msg &= " -- Parent exception: " & error.parent.msg
  return msg
