import pkg/asynctest
import pkg/ethers

suite "JsonRpcSigner":

  var provider: JsonRpcProvider

  setup:
    provider = JsonRpcProvider.new()

  test "is connected to the first account of the provider by default":
    let signer = provider.getSigner()
    check (await signer.getAddress()) == (await provider.listAccounts())[0]

  test "can connect to a different account":
    let account = (await provider.listAccounts())[1]
    let signer = provider.getSigner(account)
    check (await signer.getAddress()) == account
