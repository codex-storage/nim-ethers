import std/json
import pkg/asynctest
import pkg/chronos
import pkg/ethers
import pkg/stew/byteutils
import ./examples
import ./miner

suite "JsonRpcProvider":

  var provider: JsonRpcProvider

  setup:
    provider = JsonRpcProvider.new("ws://localhost:8545")

  test "can be instantiated with a default URL":
    discard JsonRpcProvider.new()

  test "can be instantiated with an HTTP URL":
    discard JsonRpcProvider.new("http://localhost:8545")

  test "can be instantiated with a websocket URL":
    discard JsonRpcProvider.new("ws://localhost:8545")

  test "lists all accounts":
    let accounts = await provider.listAccounts()
    check accounts.len > 0

  test "sends raw messages to the provider":
    let response = await provider.send("evm_mine")
    check response == %"0x0"

  test "returns block number":
    let blocknumber1 = await provider.getBlockNumber()
    discard await provider.send("evm_mine")
    let blocknumber2 = await provider.getBlockNumber()
    check blocknumber2 > blocknumber1

  test "returns block":
    let block1 = !await provider.getBlock(BlockTag.earliest)
    let block2 = !await provider.getBlock(BlockTag.latest)
    check block1.hash != block2.hash
    check block1.number < block2.number
    check block1.timestamp < block2.timestamp

  test "subscribes to new blocks":
    let oldBlock = !await provider.getBlock(BlockTag.latest)
    var newBlock: Block
    let blockHandler = proc(blck: Block) = newBlock = blck
    let subscription = await provider.subscribe(blockHandler)
    discard await provider.send("evm_mine")
    check newBlock.number > oldBlock.number
    check newBlock.timestamp > oldBlock.timestamp
    check newBlock.hash != oldBlock.hash
    await subscription.unsubscribe()

  test "can send a transaction":
    let signer = provider.getSigner()
    let transaction = Transaction.example
    let populated = await signer.populateTransaction(transaction)

    let txResp = await signer.sendTransaction(populated)
    check txResp.hash.len == 32 and UInt256.fromHex(txResp.hash.toHex) > 0

  test "can wait for a transaction to be confirmed":
    let signer = provider.getSigner()
    let transaction = Transaction.example
    let populated = await signer.populateTransaction(transaction)

    # must be spawned so we can get newHeads inside of .wait
    asyncSpawn provider.mineBlocks(3)

    let receipt = await signer.sendTransaction(populated).wait(3)
    let endBlock = await provider.getBlockNumber()

    check receipt.blockNumber.isSome # was eventually mined
    check (endBlock - !receipt.blockNumber) + 1 == 3 # +1 for the block the tx was mined in

  test "waiting for block to be mined times out":

    # must be spawned so we can get newHeads inside of .wait
    asyncSpawn provider.mineBlocks(10)

    let startBlock = await provider.getBlockNumber()
    let response = TransactionResponse(hash: TransactionHash.example,
                                      provider: provider)
    try:
      discard await response.wait(wantedConfirms = 2,
                                  timeoutInBlocks = 5.some)
    except JsonRpcProviderError as e:
      check e.msg == "Transaction was not mined in 5 blocks"

      let endBlock = await provider.getBlockNumber()
      check (endBlock - startBlock) + 1 == 5 # +1 including start block
