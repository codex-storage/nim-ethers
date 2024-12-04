version = "1.0.0"
author = "Nim Ethers Authors"
description = "library for interacting with Ethereum"
license = "MIT"

requires "nim >= 1.6.0"
requires "chronicles >= 0.10.3 & < 0.11.0"
requires "chronos >= 4.0.0 & < 4.1.0"
requires "contractabi >= 0.6.0 & < 0.7.0"
requires "questionable >= 0.10.2 & < 0.11.0"
requires "json_rpc >= 0.5.0 & < 0.6.0"
requires "serde >= 1.2.1 & < 1.3.0"
requires "stint >= 0.8.0 & < 0.9.0"
requires "stew >= 0.2.0 & < 0.3.0"
requires "https://github.com/codex-storage/nim-eth-versioned >= 1.0.0 & < 2.0.0"

task test, "Run the test suite":
  # exec "nimble install -d -y"
  withDir "testmodule":
    exec "nimble test"
