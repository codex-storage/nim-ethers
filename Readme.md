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
requires "ethers >= 0.2.1 & < 0.3.0"
```

Usage
-----

To connect to an Ethereum node, you require a `Provider`. Currently, only a
JSON-RPC provider is supported:

```nim
import ethers
import chronos

let provider = JsonRpcProvider.new("ws://localhost:8545")
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

You can now subscribe to Transfer events by calling `subscribe` on the contract
instance.

```nim
proc handleTransfer(transfer: Transfer) =
  echo "received transfer: ", transfer

let subscription = await token.subscribe(Transfer, handleTransfer)
```

When a Transfer event is emitted, the `handleTransfer` proc that you just
defined will be called.

When you're no longer interested in these events, you can unsubscribe:

```nim
await subscription.unsubscribe()
```

Subscriptions are currently only supported when using a JSON RPC provider that
is created with a websockets URL such as `ws://localhost:8545`.

Thanks
------

This library is inspired by the great work done by the [ethers.js][0] (no
affiliation) and [nim-web3][1] developers.

[0]: https://docs.ethers.io/
[1]: https://github.com/status-im/nim-web3
[2]: https://github.com/nim-lang/nimble
[3]: https://docs.soliditylang.org/en/v0.8.11/contracts.html#state-mutability
