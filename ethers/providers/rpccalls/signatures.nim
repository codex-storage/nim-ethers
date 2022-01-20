proc eth_accounts: seq[Address]
proc eth_blockNumber: UInt256
proc eth_call(tx: Transaction): seq[byte]
