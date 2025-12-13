import std/os
import pkg/asynctest/chronos/unittest
import pkg/chronos
import pkg/ethers
import pkg/ethers/providers/jsonrpc/conversions
import pkg/stew/byteutils
import ../../examples
import ../../miner

let providerUrl = getEnv("ETHERS_TEST_PROVIDER", "localhost:8545")
for url in ["ws://" & providerUrl, "http://"  & providerUrl]:

  suite "JsonRpcProvider (" & url & ")":

    var provider: JsonRpcProvider

    setup:
      provider = await JsonRpcProvider.connect(url, pollingInterval = 100.millis)

    teardown:
      await provider.close()

    test "can be instantiated with a default URL":
      let provider = await JsonRpcProvider.connect()
      await provider.close()

    test "lists all accounts":
      let accounts = await provider.listAccounts()
      check accounts.len > 0

    test "sends raw messages to the provider":
      let response = await provider.send("evm_mine")
      check response == %"0"

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
      discard await provider.send("evm_mine")
      var newBlock: Block
      let blockHandler = proc(blck: Block) = newBlock = blck
      let subscription = await provider.subscribe(blockHandler)
      discard await provider.send("evm_mine")
      check eventually newBlock.number.isSome
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
      for confirmations in 1..3:
        let signer = provider.getSigner()
        let transaction = Transaction.example
        let populated = await signer.populateTransaction(transaction)
        let confirming = signer.sendTransaction(populated).confirm(confirmations)
        await sleepAsync(100.millis) # wait for tx to be mined
        await provider.mineBlocks(confirmations)
        let receipt = await confirming
        check receipt.blockNumber.isSome

    test "confirmation times out":
      let hash = TransactionHash.example
      let tx = TransactionResponse(provider: provider, hash: hash)
      let confirming = tx.confirm(confirmations = 2, timeout = 5)
      await sleepAsync(100.millis) # wait for confirm to subscribe to new blocks
      await provider.mineBlocks(5)
      expect EthersError:
        discard await confirming

    test "raises JsonRpcProviderError when connect fails":
      expect JsonRpcProviderError:
        discard await JsonRpcProvider.connect("http://invalid.")

    test "syncing":
      let isSyncing = await provider.isSyncing()
      check not isSyncing

