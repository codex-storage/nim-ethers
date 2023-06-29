import std/unittest
import pkg/ethers/provider
import pkg/ethers/providers/jsonrpc/conversions

suite "JSON Conversions":

  test "missing block number in Block isNone":
    var json = %*{
      "number": newJNull(),
      "hash":"0x2d7d68c8f48b4213d232a1f12cab8c9fac6195166bb70a5fb21397984b9fe1c7",
      "timestamp":"0x6285c293"
    }

    var blk = Block.fromJson(json)
    check blk.number.isNone

    json["number"] = newJString("")

    blk = Block.fromJson(json)
    check blk.number.isSome
    check blk.number.get.isZero

  test "missing block hash in Block isNone":

    var blkJson = %*{
      "subscription": "0x20",
      "result":{
        "number": "0x1",
        "hash": newJNull(),
        "timestamp": "0x6285c293"
      }
    }

    var blk = Block.fromJson(blkJson["result"])
    check blk.hash.isNone

  test "missing block number in TransactionReceipt isNone":
    var json = %*{
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

    var receipt = TransactionReceipt.fromJson(json)
    check receipt.blockNumber.isNone

    json["blockNumber"] = newJString("")
    receipt = TransactionReceipt.fromJson(json)
    check receipt.blockNumber.isSome
    check receipt.blockNumber.get.isZero

  test "missing block hash in TransactionReceipt isNone":
    let json = %*{
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

    let receipt = TransactionReceipt.fromJson(json)
    check receipt.blockHash.isNone
