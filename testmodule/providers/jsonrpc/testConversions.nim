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

  test "newHeads subcription raises exception when deserializing to Log":
    let json = """{
      "parentHash":"0xd68d4d0f29307df51e1284fc8a13595ae700ef0f1128830a69e6854381363d42",
      "sha3Uncles":"0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
      "miner":"0x0000000000000000000000000000000000000000",
      "stateRoot":"0x1f6f2d05de35bbfd50213be96ddf960d62b978b472c55d6ac223cd648cbbbbb0",
      "transactionsRoot":"0xb9bb8a26abe091bb628ab2b6585c5af151aeb3984f4ba47a3c65d438283e069d",
      "receiptsRoot":"0x33f229b7133e1ba3fb524b8af22d8184ca10b2da5bb170092a219c61ca023c1d",
      "logsBloom":"0x00000000000000000000000000000000000000000020000000000002000000000000000000000000000000000000000000000000000008080000100200200000000000000000000000000008000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000010000040000000000100000000000800000000000000000000000000000000020000000000020000000000000000000000000000040000008000000000000000000020000000000002000000000000000000000000000000000000000000000000000001000010000000000000000020002000000020000000000000008002000000000000",
      "difficulty":"0x2",
      "number":"0x21d",
      "gasLimit":"0x1c1b59a7",
      "gasUsed":"0xda41b",
      "timestamp":"0x6509410e",
      "extraData":"0xd883010b05846765746888676f312e32302e32856c696e7578000000000000007102a27d75709b90ca9eb23cdaaccf4fc2d571d710f3bc5a7dc874f43af116a93ff832576a53c16f0d0aa1cd9e9a1dc0a60126c4d420f72b0866fc96ba6664f601",
      "mixHash":"0x0000000000000000000000000000000000000000000000000000000000000000",
      "nonce":"0x0000000000000000",
      "baseFeePerGas":"0x7",
      "withdrawalsRoot":null,
      "hash":"0x64066c7150c660e5357c4b6b02d836c10353dfa8edb32c805fca9367fd29c6e7"
    }"""
    expect ValueError:
      discard Log.fromJson(parseJson(json))

  test "getTransactionByHash correctly deserializes 'data' field from 'input' for Transaction":
    let json = %*{
      "blockHash":"0x595bffbe897e025ea2df3213c4cc52c3f3d69bc04b49011d558f1b0e70038922",
      "blockNumber":"0x22e",
      "from":"0xe00b677c29ff8d8fe6068530e2bc36158c54dd34",
      "gas":"0x4d4bb",
      "gasPrice":"0x3b9aca07",
      "hash":"0xa31608907c338d6497b0c6ec81049d845c7d409490ebf78171f35143897ca790",
      "input":"0x6368a471d26ff5c7f835c1a8203235e88846ce1a196d6e79df0eaedd1b8ed3deec2ae5c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000012a00000000000000000000000000000000000000000000000000000000000000",
      "nonce":"0x3",
      "to":"0x92f09aa59dccb892a9f5406ddd9c0b98f02ea57e",
      "transactionIndex":"0x3",
      "value":"0x0",
      "type":"0x0",
      "chainId":"0xc0de4",
      "v":"0x181bec",
      "r":"0x57ba18460934526333b80b0fea08737c363f3cd5fbec4a25a8a25e3e8acb362a",
      "s":"0x33aa50bc8bd719b6b17ad0bf52006bf8943999198f2bf731eb33c118091000f2"
    }

    let receipt = Transaction.fromJson(json)
    check receipt.data.len > 0
