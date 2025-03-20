--styleCheck:usages
--styleCheck:error

# begin Nimble config (version 1)
when fileExists("nimble.paths"):
  include "nimble.paths"
# end Nimble config

when (NimMajor, NimMinor) >= (2, 0):
  --mm:refc
  --define:ws_resubscribe
