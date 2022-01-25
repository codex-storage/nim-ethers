import std/random
import std/sequtils
import pkg/ethers

randomize()

proc example*[N](_: type array[N, byte]): array[N, byte] =
  var a: array[N, byte]
  for b in a.mitems:
    b = rand(byte)
  a

proc example*(_: type seq[byte]): seq[byte] =
  let length = rand(0..<20)
  newSeqWith(length, rand(byte))

proc example*(_: type Address): Address =
  Address.init(array[20, byte].example)

proc example*(_: type UInt256): UInt256 =
  UInt256.fromBytesBE(array[32, byte].example)

proc example*(_: type Transaction): Transaction =
  Transaction(to: Address.example, data: seq[byte].example)
