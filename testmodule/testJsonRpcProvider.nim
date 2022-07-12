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
    check !block1.number < !block2.number
    check block1.timestamp < block2.timestamp

  test "subscribes to new blocks":
    let oldBlock = !await provider.getBlock(BlockTag.latest)
    var newBlock: Block
    let blockHandler = proc(blck: Block) {.async.} = newBlock = blck
    let subscription = await provider.subscribe(blockHandler)
    discard await provider.send("evm_mine")
    check !newBlock.number > !oldBlock.number
    check newBlock.timestamp > oldBlock.timestamp
    check newBlock.hash != oldBlock.hash
    await subscription.unsubscribe()

  test "can send a transaction":
    let signer = provider.getSigner()
    let transaction = Transaction.example
    let populated = await signer.populateTransaction(transaction)

    let txResp = await signer.sendTransaction(populated)
    check txResp.hash.len == 32
    check UInt256.fromHex("0x" & txResp.hash.toHex) > 0

  test "can wait for a transaction to be confirmed":
    let signer = provider.getSigner()
    let transaction = Transaction.example
    let populated = await signer.populateTransaction(transaction)

    # must not be awaited so we can get newHeads inside of .wait
    let futMined = provider.mineBlocks(5)

    let receipt = await signer.sendTransaction(populated).confirm(3)
    let endBlock = await provider.getBlockNumber()

    check receipt.blockNumber.isSome # was eventually mined

    # >= 3 because more blocks may have been mined by the time the
    # check in `.wait` was done.
    # +1 for the block the tx was mined in
    check (endBlock - !receipt.blockNumber) + 1 >= 3

    await futMined

  test "waiting for block to be mined times out":

    # must not be awaited so we can get newHeads inside of .wait
    let futMined = provider.mineBlocks(7)

    let startBlock = await provider.getBlockNumber()
    let response = TransactionResponse(hash: TransactionHash.example,
                                      provider: provider)
    try:
      discard await response.confirm(wantedConfirms = 2,
                                     timeoutInBlocks = 5)

      await futMined
    except EthersError as e:
      check e.msg == "Transaction was not mined in 5 blocks"

      let endBlock = await provider.getBlockNumber()

      # >= 5 because more blocks may have been mined by the time the
      # check in `.wait` was done.
      # +1 for including the start block
      check (endBlock - startBlock) + 1 >= 5 # +1 including start block
      if not futMined.completed and not futMined.finished: await futMined

  test "Conversion: missing block number in Block isNone":

    var blkJson = %*{
      "subscription": "0x20",
      "result":{
        "number": newJNull(),
        "hash":"0x2d7d68c8f48b4213d232a1f12cab8c9fac6195166bb70a5fb21397984b9fe1c7",
        "timestamp":"0x6285c293"
      }
    }

    var blk = Block.fromJson(blkJson["result"])
    check blk.number.isNone

    blkJson["result"]["number"] = newJString("")

    blk = Block.fromJson(blkJson["result"])
    check blk.number.isSome
    check blk.number.get.isZero

  test "Conversion: missing block number in TransactionReceipt isNone":

    var txReceiptJson = %*{
      "sender": newJNull(),
      "to": "0x5fbdb2315678afecb367f032d93f642f64180aa3",
      "contractAddress": newJNull(),
      "transactionIndex": "0x0",
      "gasUsed": "0x10db1",
      "logsBloom": "0x00000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000840020000000000000000000800000000000000000000000010000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000020000000000000000000000000000000000001000000000000000000000000000000",
      "blockHash": "0x7b00154e06fe4f27a87208eba220efb4dbc52f7429549a39a17bba2e0d98b960",
      "transactionHash": "0xa64f07b370cbdcce381ec9bfb6c8004684341edfb6848fd418189969d4b9139c",
      "logs": [
        {
          "data": "0x0000000000000000000000000000000000000000000000000000000000000064",
          "topics": [
            "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
            "0x0000000000000000000000000000000000000000000000000000000000000000",
            "0x00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8"
          ]
        }
      ],
      "blockNumber": newJNull(),
      "cumulativeGasUsed": "0x10db1",
      "status": "0000000000000001"
    }

    var txReceipt = TransactionReceipt.fromJson(txReceiptJson)
    check txReceipt.blockNumber.isNone

    txReceiptJson["blockNumber"] = newJString("")
    txReceipt = TransactionReceipt.fromJson(txReceiptJson)
    check txReceipt.blockNumber.isSome
    check txReceipt.blockNumber.get.isZero

  test "Conversion: missing block hash in TransactionReceipt isNone":

    var txReceiptJson = %*{
      "sender": newJNull(),
      "to": "0x5fbdb2315678afecb367f032d93f642f64180aa3",
      "contractAddress": newJNull(),
      "transactionIndex": "0x0",
      "gasUsed": "0x10db1",
      "logsBloom": "0x00000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000840020000000000000000000800000000000000000000000010000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000042000000000000000000000000000000000000000000000000000020000000000000000000000000000000000001000000000000000000000000000000",
      "blockHash":  newJNull(),
      "transactionHash": "0xa64f07b370cbdcce381ec9bfb6c8004684341edfb6848fd418189969d4b9139c",
      "logs": [
        {
          "data": "0x0000000000000000000000000000000000000000000000000000000000000064",
          "topics": [
            "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
            "0x0000000000000000000000000000000000000000000000000000000000000000",
            "0x00000000000000000000000070997970c51812dc3a010c7d01b50e0d17dc79c8"
          ]
        }
      ],
      "blockNumber": newJNull(),
      "cumulativeGasUsed": "0x10db1",
      "status": "0000000000000001"
    }

    var txReceipt = TransactionReceipt.fromJson(txReceiptJson)
    check txReceipt.blockHash.isNone

  test "confirmations calculated correctly":
    # when receipt block number is higher than current block number,
    # should return 0
    check confirmations(2.u256, 1.u256) == 0.u256

    # Same receipt and current block counts as one confirmation
    check confirmations(1.u256, 1.u256) == 1.u256

    check confirmations(1.u256, 2.u256) == 2.u256

  test "checks if transation has been mined correctly":

    var receipt: TransactionReceipt
    var currentBlock = 1.u256
    var wantedConfirms = 1
    let blockHash = hexToByteArray[32](
      "0x7b00154e06fe4f27a87208eba220efb4dbc52f7429549a39a17bba2e0d98b960"
    ).some

    # missing blockHash
    receipt = TransactionReceipt(
      blockNumber: 1.u256.some
    )
    check not receipt.hasBeenMined(currentBlock, wantedConfirms)

    # missing block number
    receipt = TransactionReceipt(
      blockHash: blockHash
    )
    check not receipt.hasBeenMined(currentBlock, wantedConfirms)

    # block number is 0
    receipt = TransactionReceipt(
      blockNumber: 0.u256.some
    )
    check not receipt.hasBeenMined(currentBlock, wantedConfirms)

    # not enough confirms
    receipt = TransactionReceipt(
      blockNumber: 1.u256.some
    )
    check not receipt.hasBeenMined(currentBlock, wantedConfirms)

    # success
    receipt = TransactionReceipt(
      blockNumber: 1.u256.some,
      blockHash: blockHash
    )
    currentBlock = int.high.u256
    wantedConfirms = int.high
    check receipt.hasBeenMined(currentBlock, wantedConfirms)

  test "raises JsonRpcProviderError when something goes wrong":
    let provider = JsonRpcProvider.new("http://invalid.")
    expect JsonRpcProviderError:
      discard await provider.listAccounts()
    expect JsonRpcProviderError:
      discard await provider.send("evm_mine")
    expect JsonRpcProviderError:
      discard await provider.getBlockNumber()
    expect JsonRpcProviderError:
      discard await provider.getBlock(BlockTag.latest)
    expect JsonRpcProviderError:
      discard await provider.subscribe(proc(_: Block) {.async.} = discard)
    expect JsonRpcProviderError:
      discard await provider.getSigner().sendTransaction(Transaction.example)
