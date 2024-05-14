import pkg/ethers
import ./hardhat

type
  TestHelpers* = ref object of Contract

method doRevert*(
  self: TestHelpers,
  revertReason: string
): Confirmable {.base, contract.}

proc new*(_: type TestHelpers, signer: Signer): TestHelpers =
  let deployment = readDeployment()
  TestHelpers.new(!deployment.address(TestHelpers), signer)
