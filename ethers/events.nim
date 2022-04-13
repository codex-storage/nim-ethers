import std/macros
import pkg/contractabi
import ./basics
import ./provider

type
  Event* = object of RootObj
  ValueType = uint8 | uint16 | uint32 | uint64 | UInt256 | UInt128 |
              int8 | int16 | int32 | int64 | Int256 | Int128 |
              bool | Address
  SmallByteArray = array[ 1, byte] | array[ 2, byte] | array[ 3, byte] |
                   array[ 4, byte] | array[ 5, byte] | array[ 6, byte] |
                   array[ 7, byte] | array[ 8, byte] | array[ 9, byte] |
                   array[10, byte] | array[11, byte] | array[12, byte] |
                   array[13, byte] | array[14, byte] | array[15, byte] |
                   array[16, byte] | array[17, byte] | array[18, byte] |
                   array[19, byte] | array[20, byte] | array[21, byte] |
                   array[22, byte] | array[23, byte] | array[24, byte] |
                   array[25, byte] | array[26, byte] | array[27, byte] |
                   array[28, byte] | array[29, byte] | array[30, byte] |
                   array[31, byte] | array[32, byte]

push: {.upraises: [].}

template indexed* {.pragma.}

func decode*[E: Event](decoder: var AbiDecoder, _: type E): ?!E =
  var event: E
  decoder.startTuple()
  for field in event.fields:
    if not field.hasCustomPragma(indexed):
      field = ?decoder.read(typeof(field))
  decoder.finishTuple()
  success event

func decode*[E: Event](_: type E, data: seq[byte], topics: seq[Topic]): ?!E =
  var event = ?Abidecoder.decode(data, E)
  var i = 1
  for field in event.fields:
    if field.hasCustomPragma(indexed):
      if i >= topics.len:
        return failure "indexed event parameter not found"
      if typeof(field) is ValueType or typeof(field) is SmallByteArray:
        field = ?AbiDecoder.decode(@(topics[i]), typeof(field))
      inc i
  success event
