--styleCheck:usages
# Disable styleCheck temporarily because Nim 2.x is checking that 
# getopt is used instead of  
# https://github.com/status-im/nim-testutils/pull/54/commits/a1b07a11dd6a0c537a72e5ebf70df438c80f920a
#--styleCheck:error

# begin Nimble config (version 1)
when fileExists("nimble.paths"):
  include "nimble.paths"
# end Nimble config

when (NimMajor, NimMinor) >= (2, 0):
  --mm:refc
