import ../basics
import ../provider
import ../signer

{.push raises:[].}

type Contract* = ref object of RootObj
  provider: Provider
  signer: ?Signer
  address: Address

func new*(ContractType: type Contract,
          address: Address,
          provider: Provider): ContractType =
  ContractType(provider: provider, address: address)

func new*(ContractType: type Contract,
          address: Address,
          signer: Signer): ContractType {.raises: [SignerError].} =
  ContractType(signer: some signer, provider: signer.provider, address: address)

func connect*[C: Contract](contract: C, provider: Provider): C =
  C.new(contract.address, provider)

func connect*[C: Contract](contract: C, signer: Signer): C {.raises: [SignerError].} =
  C.new(contract.address, signer)

func provider*(contract: Contract): Provider =
  contract.provider

func signer*(contract: Contract): ?Signer =
  contract.signer

func address*(contract: Contract): Address =
  contract.address

