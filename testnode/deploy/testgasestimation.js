module.exports = async ({ deployments, getNamedAccounts }) => {
  const { deployer } = await getNamedAccounts();
  await deployments.deploy("TestGasEstimation", { from: deployer });
};

module.exports.tags = ["TestGasEstimation"];
