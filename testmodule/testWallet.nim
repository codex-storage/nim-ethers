import pkg/asynctest
import ../ethers

const pk1 = "9c0257114eb9399a2985f8e75dad7600c5d89fe3824ffa99ec1c3eb8bf3b0501"
const pk_with_funds = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

type Erc20* = ref object of Contract
proc transfer*(erc20: Erc20, recipient: Address, amount: UInt256) {.contract.}

suite "Wallet":

  #TODO add more tests. I am not sure if I am testing everything currently
  #TODO take close look at current signing tests. I am not 100% sure they are correct and work
  #TODO add setup/teardown if required. Currently doing all nonces manually

  var provider: JsonRpcProvider
  var snapshot: JsonNode

  setup:
    provider = JsonRpcProvider.new()
    snapshot = await provider.send("evm_snapshot")
  
  teardown:
    discard await provider.send("evm_revert", @[snapshot])

  test "Can create Wallet with private key":
    discard Wallet.new(pk1)

  test "Private key can start with 0x":
    discard Wallet.new("0x" & pk1)
  
  test "Can create Wallet with provider":
    let provider = JsonRpcProvider.new()
    discard Wallet.new(pk1, provider)

  test "Can connect Wallet to provider":
    let wallet = Wallet.new(pk1)
    wallet.connect(provider)
  
  test "Can create Random Wallet":
    discard Wallet.createRandom()

  test "Can create Random Wallet with provider":
    discard Wallet.createRandom(provider)

  test "Multiple Random Wallets are different":
    let wallet1 = Wallet.createRandom()
    let wallet2 = Wallet.createRandom()
    check $wallet1.privateKey != $wallet2.privateKey
  
  test "Creates the correct public key and Address from private key":
    let wallet = Wallet.new(pk1)
    check $wallet.publicKey == "5eed5fa3a67696c334762bb4823e585e2ee579aba3558d9955296d6c04541b426078dbd48d74af1fd0c72aa1a05147cf17be6b60bdbed6ba19b08ec28445b0ca"
    check $wallet.address == "0x328809bc894f92807417d2dad6b7c998c1afdac6"
  
  test "Can sign manually created transaction":
    let wallet = Wallet.new(pk1)
    let tx = Transaction(
      to: wallet.address,
      nonce: some 0.u256,
      chainId: some 31337.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 21_000.u256,
    )
    let signedTx = await wallet.signTransaction(tx)
    check signedTx == @[248.byte, 99, 128, 132, 59, 154, 202, 0, 130, 82, 8, 148, 50, 136, 9, 188, 137, 79, 146, 128, 116, 23, 210, 218, 214, 183, 201, 152, 193, 175, 218, 198, 128, 128, 27, 160, 74, 233, 178, 76, 186, 114, 16, 59, 179, 10, 30, 145, 192, 22, 121, 111, 194, 191, 45, 70, 210, 183, 92, 168, 2, 17, 250, 224, 51, 124, 60, 3, 160, 94, 60, 129, 206, 153, 68, 160, 127, 24, 182, 81, 66, 161, 132, 124, 91, 114, 249, 147, 200, 231, 194, 141, 93, 67, 96, 255, 54, 162, 254, 208, 73]
  
  test "Can sign manually created contract call":
    let wallet = Wallet.new(pk1)
    let tx = Transaction(
      to: wallet.address,
      data: @[24.byte, 22, 13, 221], # Arbitrary Calldata for totalsupply()
      nonce: some 0.u256,
      chainId: some 31337.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 21_000.u256,
    )
    let signedTx = await wallet.signTransaction(tx)
    check signedTx == @[248.byte, 103, 128, 132, 59, 154, 202, 0, 130, 82, 8, 148, 50, 136, 9, 188, 137, 79, 146, 128, 116, 23, 210, 218, 214, 183, 201, 152, 193, 175, 218, 198, 128, 132, 24, 22, 13, 221, 28, 160, 41, 38, 31, 199, 79, 251, 187, 92, 227, 208, 163, 182, 234, 201, 114, 111, 5, 216, 168, 73, 224, 241, 83, 87, 34, 224, 87, 189, 216, 59, 150, 89, 160, 68, 248, 87, 133, 43, 216, 183, 187, 140, 12, 10, 90, 97, 194, 197, 111, 206, 66, 237, 172, 171, 115, 244, 35, 1, 181, 9, 237, 183, 96, 15, 241]

  test "Can sign manually created tx with EIP1559":
    let wallet = Wallet.new(pk1)
    let tx = Transaction(
      to: wallet.address,
      nonce: some 0.u256,
      chainId: some 31337.u256,
      maxFee: some 2_000_000_000.u256,
      maxPriorityFee: some 1_000_000_000.u256,
      gasLimit: some 21_000.u256
    )
    let signedTx = await wallet.signTransaction(tx)
    check signedTx == @[2.byte, 248, 108, 130, 122, 105, 128, 132, 59, 154, 202, 0, 132, 119, 53, 148, 0, 130, 82, 8, 148, 50, 136, 9, 188, 137, 79, 146, 128, 116, 23, 210, 218, 214, 183, 201, 152, 193, 175, 218, 198, 128, 128, 192, 1, 160, 22, 41, 41, 252, 91, 76, 178, 134, 237, 76, 214, 48, 209, 114, 209, 221, 116, 125, 173, 79, 251, 235, 65, 59, 3, 127, 33, 22, 143, 79, 227, 102, 160, 98, 185, 49, 193, 252, 85, 2, 138, 225, 253, 245, 52, 37, 100, 48, 12, 174, 37, 23, 145, 215, 133, 160, 239, 211, 28, 8, 132, 5, 166, 81, 231]

  test "Can send rawTransaction":
    let wallet = Wallet.new(pk_with_funds)
    let tx = Transaction(
      to: wallet.address,
      nonce: some 0.u256,
      chainId: some 31337.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 21_000.u256,
    )
    let signedTx = await wallet.signTransaction(tx)
    let txHash = await provider.sendRawTransaction(signedTx)
    check txHash.hash == TransactionHash([167.byte, 105, 79, 222, 144, 123, 214, 138, 4, 199, 124, 181, 35, 236, 79, 93, 84, 4, 85, 172, 40, 50, 189, 187, 219, 6, 172, 98, 243, 196, 93, 64])
  
  test "Can call state-changing function automatically":
    #TODO add actual token contract, not random address. Should work regardless
    let wallet = Wallet.new(pk_with_funds, provider)
    let overrides = TransactionOverrides(
      nonce: some 0.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 22_000.u256)
    let testToken = Erc20.new(wallet.address, wallet)
    await testToken.transfer(wallet.address, 24.u256, overrides)
  
  test "Can call state-changing function automatically EIP1559":
    #TODO add actual token contract, not random address. Should work regardless
    let wallet = Wallet.new(pk_with_funds, provider)
    let overrides = TransactionOverrides(
      nonce: some 0.u256,
      maxFee: some 1_000_000_000.u256,
      maxPriorityFee: some 1_000_000_000.u256,
      gasLimit: some 22_000.u256)
    let testToken = Erc20.new(wallet.address, wallet)
    await testToken.transfer(wallet.address, 24.u256, overrides)