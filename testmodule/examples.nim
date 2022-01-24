import std/random
import std/sequtils
import pkg/ethers

randomize()

proc example*(_: type Address): Address =
  var address: array[20, byte]
  for b in address.mitems:
    b = rand(byte)
  Address.init(address)

proc example*(_: type seq[byte]): seq[byte] =
  let length = rand(0..<20)
  newSeqWith(length, rand(byte))

proc example*(_: type Transaction): Transaction =
  Transaction(to: Address.example, data: seq[byte].example)
