import std/macros
import pkg/contractabi
import ./basics
import ./provider

type
  Event* = object of RootObj
  ValueType = uint8 | uint16 | uint32 | uint64 | UInt256 | UInt128 |
              int8 | int16 | int32 | int64 | Int256 | Int128 |
              bool | Address

push: {.upraises: [].}

template indexed* {.pragma.}

func decode*[E: Event](decoder: var AbiDecoder, _: type E): ?!E =
  var event: E
  for field in event.fields:
    if not field.hasCustomPragma(indexed):
      field = ?decoder.read(typeof(field))
  success event

func decode*[E: Event](_: type E, data: seq[byte], topics: seq[Topic]): ?!E =
  var event = ?Abidecoder.decode(data, E)
  var i = 1
  for field in event.fields:
    if field.hasCustomPragma(indexed):
      if i >= topics.len:
        return failure "indexed event parameter not found"
      if typeof(field) is ValueType:
        field = ?AbiDecoder.decode(@(topics[i]), typeof(field))
      inc i
  success event
