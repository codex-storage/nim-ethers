import pkg/eth/keys
import pkg/eth/rlp
import pkg/eth/common/transaction as eth
import pkg/eth/common/eth_hash
import ../../basics
import ../../transaction as ethers
import ../../provider
import ./error
from pkg/eth/common/eth_types import EthAddress

type
  Transaction = ethers.Transaction
  SignableTransaction = eth.Transaction

func toSignableTransaction(transaction: Transaction): SignableTransaction =
  var signable: SignableTransaction

  without nonce =? transaction.nonce:
    raiseWalletError "missing nonce"

  without chainId =? transaction.chainId:
    raiseWalletError "missing chain id"

  without gasLimit =? transaction.gasLimit:
    raiseWalletError "missing gas limit"

  signable.nonce = nonce.truncate(uint64)
  signable.chainId = ChainId(chainId.truncate(uint64))
  signable.gasLimit = GasInt(gasLimit.truncate(uint64))

  signable.to = Opt.some(EthAddress(transaction.to))
  signable.value = transaction.value
  signable.payload = transaction.data

  if maxFeePerGas =? transaction.maxFeePerGas and
     maxPriorityFeePerGas =? transaction.maxPriorityFeePerGas:
    signable.txType = TxEip1559
    signable.maxFeePerGas = GasInt(maxFeePerGas.truncate(uint64))
    signable.maxPriorityFeePerGas = GasInt(maxPriorityFeePerGas.truncate(uint64))
  elif gasPrice =? transaction.gasPrice:
    signable.txType = TxLegacy
    signable.gasPrice = GasInt(gasPrice.truncate(uint64))
  else:
    raiseWalletError "missing gas price"

  signable

func sign(key: PrivateKey, transaction: SignableTransaction): seq[byte] =
  var transaction = transaction

  # Temporary V value, used to signal to the hashing function
  # that we'd like to use an EIP-155 signature
  transaction.V = uint64(transaction.chainId) * 2 + 35

  let hash = transaction.txHashNoSignature().data
  let signature = key.sign(SkMessage(hash)).toRaw()

  transaction.R = UInt256.fromBytesBE(signature[0..<32])
  transaction.S = UInt256.fromBytesBE(signature[32..<64])
  transaction.V = uint64(signature[64])

  if transaction.txType == TxLegacy:
    transaction.V += uint64(transaction.chainId) * 2 + 35

  rlp.encode(transaction)

func sign*(key: PrivateKey, transaction: Transaction): seq[byte] =
  key.sign(transaction.toSignableTransaction())

func toTransactionHash*(bytes: seq[byte]): TransactionHash =
  TransactionHash(bytes.keccakHash.data)
