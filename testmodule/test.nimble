version = "0.1.0"
author = "Nim Ethers Authors"
description = "Tests for Nim Ethers library"
license = "MIT"

requires "asynctest >= 0.4.0 & < 0.5.0"

task test, "Run the test suite":
  exec "nimble install -d -y"
  exec "nim c --define:ws_resubscribe=0 -r test"