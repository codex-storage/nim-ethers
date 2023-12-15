version = "0.7.1"
author = "Nim Ethers Authors"
description = "library for interacting with Ethereum"
license = "MIT"

requires "nim >= 1.6.16"
requires "chronicles >= 0.10.3 & < 0.11.0"
requires "chronos#head" # FIXME: change to >= 4.0.0 when chronos 4 is released
requires "contractabi >= 0.6.0 & < 0.7.0"
requires "questionable >= 0.10.2 & < 0.11.0"
requires "json_rpc"
requires "stint"
requires "stew"
requires "eth"

task test, "Run the test suite":
  exec "nimble install -d -y"
  withDir "testmodule":
    exec "nimble test"
