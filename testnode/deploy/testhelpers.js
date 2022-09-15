module.exports = async ({deployments, getNamedAccounts}) => {
  const { deployer } = await getNamedAccounts()
  await deployments.deploy('TestHelpers', { from: deployer })
}

module.exports.tags = ["TestHelpers"];
