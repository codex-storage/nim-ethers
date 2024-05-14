import pkg/stint
import pkg/ethers

export stint
export ethers

type
  Erc20Token* = ref object of Contract

  Transfer* = object of Event
    sender* {.indexed.}: Address
    receiver* {.indexed.}: Address
    value*: UInt256

  Approval* = object of Event
    owner* {.indexed.}: Address
    spender* {.indexed.}: Address
    value*: UInt256

method name*(token: Erc20Token): string {.base, contract, view.}
  ## Returns the name of the token.

method symbol*(token: Erc20Token): string {.base, contract, view.}
  ## Returns the symbol of the token, usually a shorter version of the name.

method decimals*(token: Erc20Token): uint8 {.base, contract, view.}
  ## Returns the number of decimals used to get its user representation.
  ## For example, if `decimals` equals `2`, a balance of `505` tokens should
  ## be displayed to a user as `5.05` (`505 / 10 ** 2`).

method totalSupply*(token: Erc20Token): UInt256 {.base, contract, view.}
  ## Returns the amount of tokens in existence.

method balanceOf*(token: Erc20Token,
                  account: Address): UInt256 {.base, contract, view.}
  ## Returns the amount of tokens owned by `account`.

method allowance*(token: Erc20Token,
                  owner: Address,
                  spender: Address): UInt256 {.base, contract, view.}
  ## Returns the remaining number of tokens that `spender` will be allowed
  ## to spend on behalf of `owner` through {transferFrom}. This is zero by
  ## default.
  ##
  ## This value changes when {approve} or {transferFrom} are called.

method transfer*(token: Erc20Token,
                 recipient: Address,
                 amount: UInt256): Confirmable {.base, contract.}
  ## Moves `amount` tokens from the caller's account to `recipient`.

method approve*(token: Erc20Token,
                spender: Address,
                amount: UInt256): Confirmable {.base, contract.}
  ## Sets `amount` as the allowance of `spender` over the caller's tokens.

method increaseAllowance*(token: Erc20Token,
                spender: Address,
                addedValue: UInt256): Confirmable {.base, contract.}
  ## Atomically increases the allowance granted to spender by the caller.
  ## This is an alternative to approve that can be used as a mitigation for problems described in IERC20.approve.
  ## Emits an Approval event indicating the updated allowance.
  ##
  ## WARNING: THIS IS NON-STANDARD ERC-20 FUNCTION, DOUBLE CHECK THAT YOUR TOKEN HAS IT!

method decreaseAllowance*(token: Erc20Token,
                spender: Address,
                addedValue: UInt256): Confirmable {.base, contract.}
  ## Atomically decreases the allowance granted to spender by the caller.
  ## This is an alternative to approve that can be used as a mitigation for problems described in IERC20.approve.
  ## Emits an Approval event indicating the updated allowance.
  ##
  ## WARNING: THIS IS NON-STANDARD ERC-20 FUNCTION, DOUBLE CHECK THAT YOUR TOKEN HAS IT!

method transferFrom*(token: Erc20Token,
                     spender: Address,
                     recipient: Address,
                     amount: UInt256): Confirmable {.base, contract.}
  ## Moves `amount` tokens from `spender` to `recipient` using the allowance
  ## mechanism. `amount` is then deducted from the caller's allowance.
