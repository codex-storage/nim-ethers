import std/unittest
import std/strformat

import pkg/stint
import pkg/questionable

import ethers/blocktag


type
  PredefinedTags = enum earliest, latest, pending

suite "BlockTag":
  for predefinedTag in PredefinedTags:
    test fmt"can be created with predefined special type: {predefinedTag}":
      var blockTag: BlockTag
      case predefinedTag:
      of earliest: blockTag = BlockTag.earliest
      of latest: blockTag = BlockTag.latest
      of pending: blockTag = BlockTag.pending
      check $blockTag == $predefinedTag
    
  test "can be created with a number":
    let blockTag = BlockTag.init(42.u256)
    check blockTag.number == 42.u256.some

  test "can be converted to string in hex format for BlockTags with number":
    let blockTag = BlockTag.init(42.u256)
    check $blockTag == "0x2a"

  test "can be compared for equality when BlockTag with number":
    let blockTag1 = BlockTag.init(42.u256)
    let blockTag2 = BlockTag.init(42.u256)
    let blockTag3 = BlockTag.init(43.u256)
    check blockTag1 == blockTag2
    check blockTag1 != blockTag3
  
  for predefinedTag in [BlockTag.earliest, BlockTag.latest, BlockTag.pending]:
    test fmt"can be compared for equality when predefined tag: {predefinedTag}":
      case $predefinedTag:
      of "earliest":
        check predefinedTag == BlockTag.earliest
        check predefinedTag != BlockTag.latest
        check predefinedTag != BlockTag.pending
      of "latest":
        check predefinedTag != BlockTag.earliest
        check predefinedTag == BlockTag.latest
        check predefinedTag != BlockTag.pending
      of "pending":
        check predefinedTag != BlockTag.earliest
        check predefinedTag != BlockTag.latest
        check predefinedTag == BlockTag.pending
  
  for predefinedTag in [BlockTag.earliest, BlockTag.latest, BlockTag.pending]:
    test fmt"number accessor returns None for BlockTags with string: {predefinedTag}":
      check predefinedTag.number == UInt256.none
