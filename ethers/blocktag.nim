import pkg/stint
import pkg/upraises

push: {.upraises: [].}

type
  BlockTagKind = enum
    stringBlockTag
    numberBlockTag
  BlockTag* = object
    case kind: BlockTagKind
    of stringBlockTag:
      stringValue: string
    of numberBlockTag:
      numberValue: UInt256

func init(_: type BlockTag, value: string): BlockTag =
  BlockTag(kind: stringBlockTag, stringValue: value)

func init*(_: type BlockTag, value: UInt256): BlockTag =
  BlockTag(kind: numberBlockTag, numberValue: value)

func earliest*(_: type BlockTag): BlockTag =
  BlockTag.init("earliest")

func latest*(_: type BlockTag): BlockTag =
  BlockTag.init("latest")

func pending*(_: type BlockTag): BlockTag =
  BlockTag.init("pending")

func `$`*(blockTag: BlockTag): string =
  case blockTag.kind
  of stringBlockTag:
    blockTag.stringValue
  of numberBlockTag:
    "0x" & blockTag.numberValue.toHex
