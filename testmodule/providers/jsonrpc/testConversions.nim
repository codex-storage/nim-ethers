import std/strutils
import std/unittest
import pkg/ethers/provider
import pkg/ethers/providers/jsonrpc/conversions
import pkg/questionable
import pkg/questionable/results
import pkg/serde
import pkg/stew/byteutils

func flatten(s: string): string =
  s.replace(" ")
    .replace("\n")

suite "JSON Conversions":

  test "missing block number in Block isNone":
    var json = %*{
      "number": newJNull(),
      "hash":"0x2d7d68c8f48b4213d232a1f12cab8c9fac6195166bb70a5fb21397984b9fe1c7",
      "timestamp":"0x6285c293"
    }

    let blk1 = !Block.fromJson(json)
    check blk1.number.isNone

    json["number"] = newJString("")

    let blk2 = !Block.fromJson(json)
    check blk2.number.isSome
    check blk2.number.get.isZero

  test "missing block hash in Block isNone":

    var blkJson = %*{
      "subscription": "0x20",
      "result":{
        "number": "0x1",
        "hash": newJNull(),
        "timestamp": "0x6285c293"
      }
    }

    without blk =? Block.fromJson(blkJson["result"]):
      fail
    check blk.hash.isNone

  test "missing block number in TransactionReceipt isNone":
    var json = %*{
      "from": newJNull(),
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
      "status": "0x1",
      "effectiveGasPrice": "0x3b9aca08",
      "type": "0x0"
    }

    without receipt1 =? TransactionReceipt.fromJson(json):
      fail
    check receipt1.blockNumber.isNone

    json["blockNumber"] = newJString("")
    without receipt2 =? TransactionReceipt.fromJson(json):
      fail
    check receipt2.blockNumber.isSome
    check receipt2.blockNumber.get.isZero

  test "missing block hash in TransactionReceipt isNone":
    let json = %*{
      "from": newJNull(),
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
      "status": "0x1",
      "effectiveGasPrice": "0x3b9aca08",
      "type": "0x0"
    }

    without receipt =? TransactionReceipt.fromJson(json):
      fail
    check receipt.blockHash.isNone

  test "correctly deserializes PastTransaction":
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

    without tx =? PastTransaction.fromJson(json):
      fail
    check tx.blockHash == BlockHash.fromHex("0x595bffbe897e025ea2df3213c4cc52c3f3d69bc04b49011d558f1b0e70038922")
    check tx.blockNumber == 0x22e.u256
    check tx.sender == Address.init("0xe00b677c29ff8d8fe6068530e2bc36158c54dd34").get
    check tx.gas == 0x4d4bb.u256
    check tx.gasPrice == 0x3b9aca07.u256
    check tx.hash == TransactionHash(array[32, byte].fromHex("0xa31608907c338d6497b0c6ec81049d845c7d409490ebf78171f35143897ca790"))
    check tx.input == hexToSeqByte("0x6368a471d26ff5c7f835c1a8203235e88846ce1a196d6e79df0eaedd1b8ed3deec2ae5c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000012a00000000000000000000000000000000000000000000000000000000000000")
    check tx.nonce == 0x3.u256
    check tx.to == Address.init("0x92f09aa59dccb892a9f5406ddd9c0b98f02ea57e").get
    check tx.transactionIndex == 0x3.u256
    check tx.value == 0.u256
    check tx.transactionType == some TransactionType.Legacy
    check tx.chainId == some 0xc0de4.u256
    check tx.v == 0x181bec.u256
    check tx.r == UInt256.fromBytesBE(hexToSeqByte("0x57ba18460934526333b80b0fea08737c363f3cd5fbec4a25a8a25e3e8acb362a"))
    check tx.s == UInt256.fromBytesBE(hexToSeqByte("0x33aa50bc8bd719b6b17ad0bf52006bf8943999198f2bf731eb33c118091000f2"))

  test "PastTransaction serializes correctly":
    let tx = PastTransaction(
      blockHash: BlockHash.fromHex("0x595bffbe897e025ea2df3213c4cc52c3f3d69bc04b49011d558f1b0e70038922"),
      blockNumber: 0x22e.u256,
      sender: Address.init("0xe00b677c29ff8d8fe6068530e2bc36158c54dd34").get,
      gas: 0x4d4bb.u256,
      gasPrice: 0x3b9aca07.u256,
      hash: TransactionHash(array[32, byte].fromHex("0xa31608907c338d6497b0c6ec81049d845c7d409490ebf78171f35143897ca790")),
      input: hexToSeqByte("0x6368a471d26ff5c7f835c1a8203235e88846ce1a196d6e79df0eaedd1b8ed3deec2ae5c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000012a00000000000000000000000000000000000000000000000000000000000000"),
      nonce: 0x3.u256,
      to: Address.init("0x92f09aa59dccb892a9f5406ddd9c0b98f02ea57e").get,
      transactionIndex: 0x3.u256,
      value: 0.u256,
      v: 0x181bec.u256,
      r: UInt256.fromBytesBE(hexToSeqByte("0x57ba18460934526333b80b0fea08737c363f3cd5fbec4a25a8a25e3e8acb362a")),
      s: UInt256.fromBytesBE(hexToSeqByte("0x33aa50bc8bd719b6b17ad0bf52006bf8943999198f2bf731eb33c118091000f2")),
      transactionType: some TransactionType.Legacy,
      chainId: some 0xc0de4.u256
    )
    let expected = """
      {
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
        "type":"0x0",
        "chainId":"0xc0de4",
        "value":"0x0",
        "v":"0x181bec",
        "r":"0x57ba18460934526333b80b0fea08737c363f3cd5fbec4a25a8a25e3e8acb362a",
        "s":"0x33aa50bc8bd719b6b17ad0bf52006bf8943999198f2bf731eb33c118091000f2"
      }""".flatten
    check $(%tx) == expected

  test "correctly converts PastTransaction to Transaction":
    let json = %*{
      "blockHash":"0x595bffbe897e025ea2df3213c4cc52c3f3d69bc04b49011d558f1b0e70038922",
      "blockNumber":"0x22e",
      "from":"0xe00b677c29ff8d8fe6068530e2bc36158c54dd34",
      "gas":"0x52277",
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

    without past =? PastTransaction.fromJson(json):
      fail
    check %past.toTransaction == %*{
      "to": !Address.init("0x92f09aa59dccb892a9f5406ddd9c0b98f02ea57e"),
      "data": hexToSeqByte("0x6368a471d26ff5c7f835c1a8203235e88846ce1a196d6e79df0eaedd1b8ed3deec2ae5c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000012a00000000000000000000000000000000000000000000000000000000000000"),
      "value": "0x0",
      "from": !Address.init("0xe00b677c29ff8d8fe6068530e2bc36158c54dd34"),
      "nonce": 0x3.u256,
      "chainId": 0xc0de4.u256,
      "gasPrice": 0x3b9aca07.u256,
      "gas": 0x52277.u256
    }

  test "correctly deserializes BlockTag":
    check !BlockTag.fromJson(newJString("earliest")) == BlockTag.earliest
    check !BlockTag.fromJson(newJString("latest")) == BlockTag.latest
    check !BlockTag.fromJson(newJString("pending")) == BlockTag.pending
    check !BlockTag.fromJson(newJString("0x1")) == BlockTag.init(1.u256)

  test "fails to deserialize BlockTag from an empty string":
    let res = BlockTag.fromJson(newJString(""))
    check res.error of SerializationError
    check res.error.msg == "Failed to convert '\"\"' to BlockTag: must be one of 'earliest', 'latest', 'pending'"
