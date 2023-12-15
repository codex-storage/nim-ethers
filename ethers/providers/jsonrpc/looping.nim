template untilCancelled*(body) =
  try:
    while true:
      body
  except CancelledError as exc:
    raise exc
