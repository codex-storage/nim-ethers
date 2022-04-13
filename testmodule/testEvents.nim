import pkg/asynctest
import pkg/ethers
import pkg/contractabi
import ./examples

suite "Events":

  type
    SimpleEvent = object of Event
      a: UInt256
      b: Address
    DynamicSizeEvent = object of Event
      a: array[32, byte]
      b: seq[byte]
    IndexedEvent = object of Event
      a: UInt256
      b {.indexed.}: Address
      c: Address
      d {.indexed.}: UInt256
      e {.indexed.}: array[32, byte]
    ComplexIndexedEvent = object of Event
      a {.indexed.}: array[42, UInt256]
      b {.indexed.}: seq[UInt256]
      c {.indexed.}: string
      d {.indexed.}: seq[byte]
      e {.indexed.}: (Address, UInt256)
      f {.indexed.}: array[33, byte]

  proc example(_: type SimpleEvent): SimpleEvent =
    SimpleEvent(
      a: UInt256.example,
      b: Address.example
    )

  proc example(_: type DynamicSizeEvent): DynamicSizeEvent =
    DynamicSizeEvent(
      a: array[32, byte].example,
      b: seq[byte].example
    )

  proc example(_: type IndexedEvent): IndexedEvent =
    IndexedEvent(
      a: UInt256.example,
      b: Address.example,
      c: Address.example,
      d: UInt256.example,
      e: array[32, byte].example
    )

  func encode[T](_: type Topic, value: T): Topic =
    let encoded = AbiEncoder.encode(value)
    result[0..<Topic.len] = encoded[0..<Topic.len]

  test "decodes event fields":
    let event = SimpleEvent.example
    let data = AbiEncoder.encode( (event.a, event.b) )
    check SimpleEvent.decode(data, @[]) == success event

  test "decodes dynamically sized fields":
    let event = DynamicSizeEvent.example
    let data = AbiEncoder.encode( (event.a, event.b) )
    check DynamicSizeEvent.decode(data, @[]) == success event

  test "decodes indexed fields":
    let event = IndexedEvent.example
    var topics: seq[Topic]
    topics.add Topic.default
    topics.add Topic.encode(event.b)
    topics.add Topic.encode(event.d)
    topics.add Topic.encode(event.e)
    let data = AbiEncoder.encode( (event.a, event.c) )
    check IndexedEvent.decode(data, topics) == success event

  test "fails when data is incomplete":
    let event = SimpleEvent.example
    let invalid = AbiEncoder.encode( (event.a,) )
    check SimpleEvent.decode(invalid, @[]).isFailure

  test "fails when topics are incomplete":
    let event = IndexedEvent.example
    var invalid: seq[Topic]
    invalid.add Topic.default
    invalid.add Topic.encode(event.b)
    let data = AbiEncoder.encode( (event.a, event.c) )
    check IndexedEvent.decode(data, invalid).isFailure

  test "ignores indexed complex arguments":
    let topics = @[
      Topic.default,
      Topic.example,
      Topic.example,
      Topic.example,
      Topic.example,
      Topic.example,
      Topic.example
    ]
    check ComplexIndexedEvent.decode(@[], topics) == success ComplexIndexedEvent()
