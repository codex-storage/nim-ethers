import std/macros
import pkg/contractabi
import ./basics
import ./provider

type
  Event* = object of RootObj

{.push raises:[].}

template indexed* {.pragma.}

func decode*[E: Event](decoder: var AbiDecoder, _: type E): ?!E =
  var event: E
  decoder.startTuple()
  for field in event.fields:
    if not field.hasCustomPragma(indexed):
      field = ?decoder.read(typeof(field))
  decoder.finishTuple()
  success event

func fitsInIndexedField(T: type): bool {.compileTime.} =
  const supportedTypes = [
    "uint8", "uint16", "uint32", "uint64", "uint256", "uint128",
    "int8",  "int16",  "int32",  "int64",  "int256",  "int128",
    "bool", "address",
    "bytes1", "bytes2", "bytes3", "bytes4",
    "bytes5", "bytes6", "bytes7", "bytes8",
    "bytes9", "bytes10", "bytes11", "bytes12",
    "bytes13", "bytes14", "bytes15", "bytes16",
    "bytes17", "bytes18", "bytes19", "bytes20",
    "bytes21", "bytes22", "bytes23", "bytes24",
    "bytes25", "bytes26", "bytes27", "bytes28",
    "bytes29", "bytes30", "bytes31", "bytes32"
  ]

  solidityType(T) in supportedTypes

func decode*[E: Event](_: type E, data: seq[byte], topics: seq[Topic]): ?!E =
  var event = ?AbiDecoder.decode(data, E)
  var i = 1
  for field in event.fields:
    if field.hasCustomPragma(indexed):
      if i >= topics.len:
        return failure "indexed event parameter not found"
      when typeof(field).fitsInIndexedField:
        field = ?AbiDecoder.decode(@(topics[i]), typeof(field))
      inc i
  success event
