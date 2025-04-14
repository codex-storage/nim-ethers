import std/os
import pkg/asynctest/chronos/unittest
import pkg/serde
import pkg/stew/byteutils
import ../ethers

const pk1 = "9c0257114eb9399a2985f8e75dad7600c5d89fe3824ffa99ec1c3eb8bf3b0501"
const pk_with_funds = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

type Erc20* = ref object of Contract
proc transfer*(erc20: Erc20, recipient: Address, amount: UInt256) {.contract.}

suite "Wallet":
  var provider: JsonRpcProvider
  var snapshot: JsonNode
  let providerUrl = getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")

  setup:
    provider = JsonRpcProvider.new("http://" & providerUrl)
    snapshot = await provider.send("evm_snapshot")

  teardown:
    discard await provider.send("evm_revert", @[snapshot])
    await provider.close()

  test "Can create Wallet with private key":
    check isSuccess Wallet.new(pk1)
    discard Wallet.new(PrivateKey.fromHex(pk1).get)

  test "Private key can start with 0x":
    check isSuccess Wallet.new("0x" & pk1)

  test "Can create Wallet with provider":
    let provider = JsonRpcProvider.new()
    check isSuccess Wallet.new(pk1, provider)
    discard Wallet.new(PrivateKey.fromHex(pk1).get, provider)

  test "Cannot create wallet with invalid key string":
    check isFailure Wallet.new("0xInvalidKey")
    check isFailure Wallet.new("0xInvalidKey", JsonRpcProvider.new())

  test "Can connect Wallet to provider":
    let wallet = !Wallet.new(pk1)
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
    let wallet = !Wallet.new(pk1)
    check $wallet.publicKey == "5eed5fa3a67696c334762bb4823e585e2ee579aba3558d9955296d6c04541b426078dbd48d74af1fd0c72aa1a05147cf17be6b60bdbed6ba19b08ec28445b0ca"
    check $wallet.address == "0x328809bc894f92807417d2dad6b7c998c1afdac6"

  test "Can sign manually created transaction":
    # Example from EIP-155
    let wallet = !Wallet.new("0x4646464646464646464646464646464646464646464646464646464646464646")
    let transaction = Transaction(
      to: !Address.init("0x3535353535353535353535353535353535353535"),
      nonce: some 9.u256,
      chainId: some 1.u256,
      gasPrice: some 20 * 10.u256.pow(9),
      gasLimit: some 21000.u256,
      value: 10.u256.pow(18),
      data: @[]
    )
    let signed = await wallet.signTransaction(transaction)
    check signed.toHex == "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"

  test "Can sign manually created tx with EIP1559":
    let wallet = !Wallet.new(pk1)
    let tx = Transaction(
      to: wallet.address,
      nonce: some 0.u256,
      chainId: some 31337.u256,
      maxFeePerGas: some 2_000_000_000.u256,
      maxPriorityFeePerGas: some 1_000_000_000.u256,
      gasLimit: some 21_000.u256
    )
    let signedTx = await wallet.signTransaction(tx)
    check signedTx.toHex == "02f86c827a6980843b9aca00847735940082520894328809bc894f92807417d2dad6b7c998c1afdac68080c001a0162929fc5b4cb286ed4cd630d172d1dd747dad4ffbeb413b037f21168f4fe366a062b931c1fc55028ae1fdf5342564300cae251791d785a0efd31c088405a651e7"

  test "Can send rawTransaction":
    let wallet = !Wallet.new(pk_with_funds)
    let tx = Transaction(
      to: wallet.address,
      nonce: some 0.u256,
      chainId: some 31337.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 21_000.u256,
    )
    let signedTx = await wallet.signTransaction(tx)
    let txHash = await provider.sendTransaction(signedTx)
    check txHash.hash != TransactionHash.default

  test "Can call state-changing function automatically":
    #TODO add actual token contract, not random address. Should work regardless
    let wallet = !Wallet.new(pk_with_funds, provider)
    let overrides = TransactionOverrides(
      nonce: some 0.u256,
      gasPrice: some 1_000_000_000.u256,
      gasLimit: some 22_000.u256)
    let testToken = Erc20.new(wallet.address, wallet)
    await testToken.transfer(wallet.address, 24.u256, overrides)

  test "Can call state-changing function automatically EIP1559":
    #TODO add actual token contract, not random address. Should work regardless
    let wallet = !Wallet.new(pk_with_funds, provider)
    let overrides = TransactionOverrides(
      nonce: some 0.u256,
      maxFeePerGas: some 1_000_000_000.u256,
      maxPriorityFeePerGas: some 1_000_000_000.u256,
      gasLimit: some 22_000.u256)
    let testToken = Erc20.new(wallet.address, wallet)
    await testToken.transfer(wallet.address, 24.u256, overrides)
