module.exports = async ({ deployments, getNamedAccounts }) => {
  const { deployer } = await getNamedAccounts();
  await deployments.deploy("TestCustomErrors", { from: deployer });
};

module.exports.tags = ["TestCustomErrors"];
