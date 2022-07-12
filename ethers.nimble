version = "0.2.0"
author = "Nim Ethers Authors"
description = "library for interacting with Ethereum"
license = "MIT"

requires "chronos >= 3.0.0 & < 4.0.0"
requires "contractabi >= 0.4.5 & < 0.5.0"
requires "questionable >= 0.10.2 & < 0.11.0"
requires "upraises >= 0.1.0 & < 0.2.0"
requires "json_rpc"
requires "stint"
requires "stew"
requires "eth"

task test, "Run the test suite":
  exec "nimble install -d -y"
  withDir "testmodule":
    exec "nimble test"
