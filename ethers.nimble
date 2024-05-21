version = "0.8.0"
author = "Nim Ethers Authors"
description = "library for interacting with Ethereum"
license = "MIT"

requires "nim >= 1.6.0"
requires "chronicles >= 0.10.3 & < 0.11.0"
requires "chronos >= 4.0.0 & < 4.1.0"
requires "contractabi >= 0.6.0 & < 0.7.0"
requires "questionable >= 0.10.2 & < 0.11.0"
requires "json_rpc >= 0.4.0 & < 0.5.0"
requires "serde >= v1.2.1 < 1.3.0"
requires "stint"
requires "stew"
requires "eth"

task test, "Run the test suite":
  exec "nimble install -d -y"
  withDir "testmodule":
    exec "nimble test"
