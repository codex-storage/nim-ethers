template untilCancelled*(body) =
  try:
    while true:
      body
  except CancelledError:
    raise
