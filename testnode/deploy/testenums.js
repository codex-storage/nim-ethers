module.exports = async ({ deployments, getNamedAccounts }) => {
  const { deployer } = await getNamedAccounts();
  await deployments.deploy("TestEnums", { from: deployer });
};

module.exports.tags = ["TestEnums"];
