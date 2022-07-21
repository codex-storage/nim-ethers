proc net_version(): string
proc eth_accounts: seq[Address]
proc eth_blockNumber: UInt256
proc eth_call(transaction: Transaction, blockTag: BlockTag): seq[byte]
proc eth_gasPrice(): UInt256
proc eth_getBlockByNumber(blockTag: BlockTag, includeTransactions: bool): ?Block
proc eth_getTransactionCount(address: Address, blockTag: BlockTag): UInt256
proc eth_estimateGas(transaction: Transaction): UInt256
proc eth_chainId(): UInt256
proc eth_sendTransaction(transaction: Transaction): TransactionHash
proc eth_getTransactionReceipt(hash: TransactionHash): ?TransactionReceipt
proc eth_sign(account: Address, message: seq[byte]): seq[byte]
proc eth_subscribe(name: string, filter: Filter): JsonNode
proc eth_subscribe(name: string): JsonNode
proc eth_unsubscribe(id: JsonNode): bool
