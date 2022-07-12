import pkg/asynctest
import ../ethers

const pk1 = "9c0257114eb9399a2985f8e75dad7600c5d89fe3824ffa99ec1c3eb8bf3b0501"
const pk_with_funds = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

type Erc20* = ref object of Contract
proc transfer*(erc20: Erc20, recipient: Address, amount: UInt256) {.contract.}

suite "Wallet":

  test "Can create Wallet with private key":
    discard Wallet.new(pk1)

  test "Private key can start with 0x":
    discard Wallet.new("0x" & pk1)
  
  test "Can create Wallet with provider":
    let provider = JsonRpcProvider.new()
    discard Wallet.new(pk1, provider)

  test "Can connect Wallet to provider":
    let provider = JsonRpcProvider.new()
    let wallet = Wallet.new(pk1)
    wallet.connect(provider)
  
  test "Can create Random Wallet":
    discard Wallet.createRandom()

  test "Can create Random Wallet with provider":
    let provider = JsonRpcProvider.new()
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
    check signedTx == "0xf86380843b9aca0082520894328809bc894f92807417d2dad6b7c998c1afdac680801ba04ae9b24cba72103bb30a1e91c016796fc2bf2d46d2b75ca80211fae0337c3c03a05e3c81ce9944a07f18b65142a1847c5b72f993c8e7c28d5d4360ff36a2fed049"
  
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
    check signedTx == "0xf86780843b9aca0082520894328809bc894f92807417d2dad6b7c998c1afdac6808418160ddd1ca029261fc74ffbbb5ce3d0a3b6eac9726f05d8a849e0f1535722e057bdd83b9659a044f857852bd8b7bb8c0c0a5a61c2c56fce42edacab73f42301b509edb7600ff1"

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
    check signedTx == "0x02f86c827a6980843b9aca00847735940082520894328809bc894f92807417d2dad6b7c998c1afdac68080c001a0162929fc5b4cb286ed4cd630d172d1dd747dad4ffbeb413b037f21168f4fe366a062b931c1fc55028ae1fdf5342564300cae251791d785a0efd31c088405a651e7"

  test "Can send rawTransaction":
    let provider = JsonRpcProvider.new()
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
    let provider = JsonRpcProvider.new()
    let wallet = Wallet.new(pk_with_funds, provider)
    let overrides = TransactionOverrides(
      nonce: some 1.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 22_000.u256)
    let testToken = Erc20.new(wallet.address, wallet)
    await testToken.transfer(wallet.address, 24.u256, overrides)
  
  test "Can call state-changing function automatically EIP1559":
    #TODO add actual token contract, not random address. Should work regardless
    let provider = JsonRpcProvider.new()
    let wallet = Wallet.new(pk_with_funds, provider)
    let overrides = TransactionOverrides(
      nonce: some 2.u256,
      maxFee: some 1_000_000_000.u256,
      maxPriorityFee: some 1_000_000_000.u256,
      gasLimit: some 22_000.u256)
    let testToken = Erc20.new(wallet.address, wallet)
    await testToken.transfer(wallet.address, 24.u256, overrides)