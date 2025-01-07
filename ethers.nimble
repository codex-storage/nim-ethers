version = "1.1.0"
author = "Nim Ethers Authors"
description = "library for interacting with Ethereum"
license = "MIT"

requires "nim >= 2.0.14"
requires "chronicles >= 0.10.3 & < 0.11.0"
requires "chronos >= 4.0.0 & < 4.1.0"

# Branch update-to-nim-2-x 
requires "contractabi#842f48910be4f388bcbf8abf1f02aba1d5e2ee64"

requires "questionable >= 0.10.2 & < 0.11.0"
requires "json_rpc >= 0.5.0 & < 0.6.0"
requires "serde >= 1.2.1 & < 1.3.0"
requires "stint >= 0.8.0 & < 0.9.0"
requires "stew >= 0.2.0 & < 0.3.0"

# Branch update-to-nim-2-x 
requires "https://github.com/codex-storage/nim-eth-versioned#98c65e74ff5a5e9647a5043b5784e5c8dc4f9fbc"

task test, "Run the test suite":
  # exec "nimble install -d -y"
  withDir "testmodule":
    exec "nimble test"
