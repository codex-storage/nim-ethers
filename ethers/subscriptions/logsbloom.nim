import pkg/eth/bloom
import ../basics
import ../provider

func contains*(blck: Block, filter: EventFilter): bool =
  without logsBloom =? blck.logsBloom:
    return false
  let bloomFilter = BloomFilter(value: logsBloom)
  if filter.address.toArray notin bloomFilter:
    return false
  for topic in filter.topics:
    if topic notin bloomFilter:
      return false
  return true
