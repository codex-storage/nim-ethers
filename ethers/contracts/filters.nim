import std/sequtils
import pkg/contractabi
import ../basics
import ../provider
import ./contract
import ./events
import ./fields

type EventHandler*[E: Event] = proc(event: E) {.gcsafe, raises:[].}

proc subscribe*[E: Event](contract: Contract,
                          _: type E,
                          handler: EventHandler[E]):
                         Future[Subscription] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = EventFilter(address: contract.address, topics: @[topic])

  proc logHandler(log: Log) {.raises: [].} =
    if event =? E.decode(log.data, log.topics):
      handler(event)

  contract.provider.subscribe(filter, logHandler)

proc queryFilter[E: Event](contract: Contract,
                            _: type E,
                            filter: EventFilter):
                           Future[seq[E]] {.async.} =

  var logs = await contract.provider.getLogs(filter)
  logs.keepItIf(not it.removed)

  var events: seq[E] = @[]
  for log in logs:
    if event =? E.decode(log.data, log.topics):
      events.add event

  return events

proc queryFilter*[E: Event](contract: Contract,
                            _: type E):
                           Future[seq[E]] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = EventFilter(address: contract.address,
                           topics: @[topic])

  contract.queryFilter(E, filter)

proc queryFilter*[E: Event](contract: Contract,
                            _: type E,
                            blockHash: BlockHash):
                           Future[seq[E]] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = FilterByBlockHash(address: contract.address,
                                 topics: @[topic],
                                 blockHash: blockHash)

  contract.queryFilter(E, filter)

proc queryFilter*[E: Event](contract: Contract,
                            _: type E,
                            fromBlock: BlockTag,
                            toBlock: BlockTag):
                           Future[seq[E]] =

  let topic = topic($E, E.fieldTypes).toArray
  let filter = Filter(address: contract.address,
                      topics: @[topic],
                      fromBlock: fromBlock,
                      toBlock: toBlock)

  contract.queryFilter(E, filter)
