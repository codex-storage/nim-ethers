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

method name*(erc20: Erc20Token): string {.base, contract, view.}
## Returns the name of the token.

method symbol*(token: Erc20Token): string {.base, contract, view.}
## Returns the symbol of the token, usually a shorter version of the name.

method decimals*(token: Erc20Token): uint8 {.base, contract, view.}
## Returns the number of decimals used to get its user representation.
## For example, if `decimals` equals `2`, a balance of `505` tokens should
## be displayed to a user as `5.05` (`505 / 10 ** 2`).

method totalSupply*(erc20: Erc20Token): UInt256 {.base, contract, view.}
## Returns the amount of tokens in existence.

method balanceOf*(erc20: Erc20Token, account: Address): UInt256 {.base, contract, view.}
## Returns the amount of tokens owned by `account`.

method allowance*(erc20: Erc20Token, owner, spender: Address): UInt256 {.base, contract, view.}
## Returns the remaining number of tokens that `spender` will be allowed
## to spend on behalf of `owner` through {transferFrom}. This is zero by default.
##
## This value changes when {approve} or {transferFrom} are called.

method transfer*(erc20: Erc20Token, recipient: Address, amount: UInt256) {.base, contract.}
## Moves `amount` tokens from the caller's account to `recipient`.

method approve*(token: Erc20Token, spender: Address, amount: UInt256) {.base, contract.}
## Sets `amount` as the allowance of `spender` over the caller's tokens.

method transferFrom*(erc20: Erc20Token, spender: Address, recipient: Address, amount: UInt256) {.base, contract.}
## Moves `amount` tokens from `from` to `to` using the allowance
## mechanism. `amount` is then deducted from the caller's allowance.

