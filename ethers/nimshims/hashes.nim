## Fixes an underlying Exception caused by missing forward declarations for
## `std/json.JsonNode.hash`, eg when using `JsonNode` as a `Table` key. Adds
## {.raises: [].} for proper exception tracking. Copied from the std/json module

import std/json
import std/hashes

{.push raises:[].}

when (NimMajor) >= 2:
  proc hash*[A](x: openArray[A]): Hash =
    ## Efficient hashing of arrays and sequences.
    ## There must be a `hash` proc defined for the element type `A`.
    when A is byte:
      result = murmurHash(x)
    elif A is char:
      when nimvm:
        result = hashVmImplChar(x, 0, x.high)
      else:
        result = murmurHash(toOpenArrayByte(x, 0, x.high))
    else:
      for a in x:
        result = result !& hash(a)
      result = !$result

func hash*(n: OrderedTable[string, JsonNode]): Hash

func hash*(n: JsonNode): Hash =
  ## Compute the hash for a JSON node
  case n.kind
  of JArray:
    result = hash(n.elems)
  of JObject:
    result = hash(n.fields)
  of JInt:
    result = hash(n.num)
  of JFloat:
    result = hash(n.fnum)
  of JBool:
    result = hash(n.bval.int)
  of JString:
    result = hash(n.str)
  of JNull:
    result = Hash(0)

func hash*(n: OrderedTable[string, JsonNode]): Hash =
  for key, val in n:
    result = result xor (hash(key) !& hash(val))
  result = !$result