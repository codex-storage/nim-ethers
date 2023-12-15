version = "0.1.0"
author = "Nim Ethers Authors"
description = "Tests for Nim Ethers library"
license = "MIT"

requires "asynctest#head" # FIXME change to 0.4.3 once we get a release
requires "questionable >= 0.10.3 & < 0.11.0"

task test, "Run the test suite":
  exec "nimble install -d -y"
  exec "nim c -r test"
