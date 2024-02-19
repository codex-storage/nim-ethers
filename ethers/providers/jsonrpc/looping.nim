template untilCancelled*(body) =
  try:
    while true:
      body
  except CancelledError as e:
    raise e
