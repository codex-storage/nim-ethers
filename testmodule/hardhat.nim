import std/json
import pkg/ethers/basics

type Deployment* = object
  json: JsonNode

const defaultFile = "../testnode/deployment.json"

## Reads deployment information from a json file. It expects a file that has
## been exported with Hardhat deploy. See also:
## https://github.com/wighawag/hardhat-deploy/tree/master#6-hardhat-export
proc readDeployment*(file = defaultFile): Deployment =
  Deployment(json: parseFile(file))

proc address*(deployment: Deployment, contract: string|type): ?Address =
  let address = deployment.json["contracts"][$contract]["address"].getStr()
  Address.init(address)
