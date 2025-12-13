Nim Ethers
==========

A port of the [ethers.js][0] library to Nim. Allows you to connect to an
Ethereum node.

This is very much a work in progress; expect to see many things that are
incomplete or wrong. Use at your own risk.

Installation
------------

Use the [Nimble][2] package manager to add `ethers` to an existing
project. Add the following to its .nimble file:

```nim
requires "ethers >= 2.0.0 & < 3.0.0"
```

To avoid conflicts with previous versions of `contractabi`, use the following command to install dependencies:

```bash
nimble install --maximumtaggedversions=2
```

Usage
-----

To connect to an Ethereum node, you require a `Provider`. Currently, only a
JSON-RPC provider is supported:

```nim
import ethers
import chronos

let provider = await JsonRpcProvider.connect("ws://localhost:8545")
let accounts = await provider.listAccounts()
```

To interact with a smart contract, you need to define the contract functions in
Nim. For example, to interact with an ERC20 token, you could define the
following:

```nim
type Erc20 = ref object of Contract

proc totalSupply(token: Erc20): UInt256 {.contract, view.}
proc balanceOf(token: Erc20, account: Address): UInt256 {.contract, view.}
proc transfer(token: Erc20, recipient: Address, amount: UInt256) {.contract.}
proc allowance(token: Erc20, owner, spender: Address): UInt256 {.contract, view.}
proc approve(token: Erc20, spender: Address, amount: UInt256) {.contract.}
proc transferFrom(token: Erc20, sender, recipient: Address, amount: UInt256) {.contract.}
```

Notice how some functions are annotated with a `{.view.}` pragma. This indicates
that the function does not modify the blockchain. See also the Solidity
documentation on [state mutability][3]

Now that you've defined the contract interface, you can create an instance of
it using its deployed address:

```nim
let address = Address.init("0x.....")
let token = Erc20.new(address, provider)
```

The functions that you defined earlier can now be called asynchronously:

```nim
let supply = await token.totalSupply()
let balance = await token.balanceOf(accounts[0])
```

These invocations do not yet change the state of the blockchain, even when we
invoke those functions that lack a `{.view.}` pragma. To allow these changes to
happen, we require an instance of a `Signer` first.

For example, to use the 4th account on the Ethereum node to sign transactions,
you'd instantiate the signer as follows:

```nim
let signer = provider.getSigner(accounts[3])
```

And then connect the contract and signer:

```nim
let writableToken = token.connect(signer)
```

This allows you to make changes to the state of the blockchain:

```nim
await writableToken.transfer(accounts[7], 42.u256)
```

Which transfers 42 tokens from account 3 to account 7

And lastly, don't forget to close the provider when you're done:

```nim
await provider.close()
```

Events
------

You can subscribe to events that are emitted by a smart contract. For instance,
to get notified about token transfers you define the `Transfer` event:

```nim
type Transfer = object of Event
  sender {.indexed.}: Address
  receiver {.indexed.}: Address
  value: UInt256
```

Notice that `Transfer` inherits from `Event`, and that some event parameters are
marked with `{.indexed.}` to match the definition in Solidity.

Note that valid types of indexed parameters are:
```nim
uint8 | uint16 | uint32 | uint64 | UInt256 | UInt128 |
int8 | int16 | int32 | int64 | Int256 | Int128 |
bool | Address | array[ 1..32, byte]
```
Distinct types of valid types are also supported for indexed fields, eg:
```nim
type
  DistinctAlias = distinct array[32, byte]
  MyEvent = object of Event
    a {.indexed.}: DistinctAlias
    b: DistinctAlias # also allowed for non-indexed fields
```

You can now subscribe to Transfer events by calling `subscribe` on the contract
instance.

```nim
proc handleTransfer(transferResult: Transfer) =
  echo "received transfer: ", transferResult.value

let subscription = await token.subscribe(Transfer, handleTransfer)
```

When a Transfer event is emitted, the `handleTransfer` proc that you just
defined will be called with a [Result](https://github.com/arnetheduck/nim-results) type
which contains the event value.

In case there is some underlying error in the event subscription, the handler will
be called as well, but the Result will contain error instead, so do proper error
management in your handlers.

When you're no longer interested in these events, you can unsubscribe:

```nim
await subscription.unsubscribe()
```

Custom errors
-------------

Solidity's [custom errors][4] are supported. To use them, you declare their type
and indicate in which contract functions they can occur. For instance, this is
how you would define the "InsufficientBalance" error to match the definition in
[this Solidity example][5]:

```nim
type
  InsufficientBalance = object of SolidityError
    arguments: tuple[available: UInt256, required: UInt256]
```

Notice that `InsufficientBalance` inherits from `SoldityError`, and that it has
an `arguments` tuple whose fields match the definition in Solidity.

You can use the `{.errors.}` pragma to declare that this error may occur in a
contract function:

```nim
proc transfer*(token: Erc20Token, recipient: Address, amount: UInt256)
  {.contract, errors:[InsufficientBalance].}
```

This allows you to write error handling code for the `transfer` function like
this:

```nim
try:
  await token.transfer(recipient, 100.u256)
except InsufficientBalance as error:
  echo "insufficient balance"
  echo "available balance: ", error.arguments.available
  echo "required balance: ", error.arguments.required
```

Utilities
---------

This library ships with some optional modules that provides convenience utilities for you such as:

- `ethers/erc20` module provides you with ERC20 token implementation and its events

Contribution
------------

If you want to run the tests, then before running `nimble test`, you have to
have installed NodeJS and started a testing node:

```shell
$ cd testnode
$ npm ci
$ npm start
```

If you need to use different port for the RPC node, then you can start with `npm start -- --port 1111` and
then run the tests with `ETHERS_TEST_PROVIDER=1111 nimble test`.

Thanks
------

This library is inspired by the great work done by the [ethers.js][0] (no
affiliation) and [nim-web3][1] developers.

[0]: https://docs.ethers.io/
[1]: https://github.com/status-im/nim-web3
[2]: https://github.com/nim-lang/nimble
[3]: https://docs.soliditylang.org/en/v0.8.11/contracts.html#state-mutability
[4]: https://docs.soliditylang.org/en/v0.8.25/contracts.html#errors-and-the-revert-statement
[5]: https://soliditylang.org/blog/2021/04/21/custom-errors/
