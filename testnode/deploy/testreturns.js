module.exports = async ({ deployments, getNamedAccounts }) => {
  const { deployer } = await getNamedAccounts();
  await deployments.deploy("TestReturns", { from: deployer });
};

module.exports.tags = ["TestReturns"];
