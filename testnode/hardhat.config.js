require("hardhat-deploy")
require("hardhat-deploy-ethers")

module.exports = {
  solidity: "0.8.11",
  namedAccounts: {
    deployer: { default: 0 }
  }
}
