proc eth_accounts: seq[Address]
proc eth_blockNumber: UInt256
proc eth_call(transaction: Transaction): seq[byte]
proc eth_gasPrice(): UInt256
proc eth_getTransactionCount(address: Address, blockTag: BlockTag): UInt256
proc eth_estimateGas(transaction: Transaction): UInt256
