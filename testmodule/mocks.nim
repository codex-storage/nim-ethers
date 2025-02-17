import pkg/ethers

type MockSigner* = ref object of Signer
  provider: Provider
  address*: Address
  transactions*: seq[Transaction]

func new*(_: type MockSigner, provider: Provider): MockSigner =
  MockSigner(provider: provider)

method provider*(signer: MockSigner): Provider =
  signer.provider

method getAddress*(
  signer: MockSigner): Future[Address]
  {.async: (raises:[ProviderError, SignerError, CancelledError]).} =

  return signer.address

method sendTransaction*(
  signer: MockSigner,
  transaction: Transaction): Future[TransactionResponse]
  {.async: (raises:[SignerError, ProviderError, CancelledError]).} =

  signer.transactions.add(transaction)
