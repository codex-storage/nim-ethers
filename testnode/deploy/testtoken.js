module.exports = async ({deployments, getNamedAccounts}) => {
  const { deployer } = await getNamedAccounts()
  await deployments.deploy('TestToken', { from: deployer })
}

module.exports.tags = ['TestToken']
