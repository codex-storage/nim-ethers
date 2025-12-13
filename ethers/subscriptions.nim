import std/tables
import std/sequtils
import ./basics
import ./provider
import ./subscriptions/blocksubscriber
import ./subscriptions/logsbloom

type
  Subscriptions* = ref object
    provider: Provider
    blockSubscriber: BlockSubscriber
    blockSubscriptions: Table[SubscriptionId, BlockHandler]
    logSubscriptions: Table[SubscriptionId, (EventFilter, LogHandler)]
    nextSubscriptionId: int
  LocalSubscription* = ref object of Subscription
    subscriptions: Subscriptions
    id: SubscriptionId
  SubscriptionId = int

func len*(subscriptions: Subscriptions): int =
  subscriptions.blockSubscriptions.len + subscriptions.logSubscriptions.len

proc subscribe*(
  subscriptions: Subscriptions,
  onBlock: BlockHandler
): Future[Subscription] {.async:(raises:[ProviderError, CancelledError]).} =
  let id = subscriptions.nextSubscriptionId
  inc subscriptions.nextSubscriptionId
  subscriptions.blockSubscriptions[id] = onBlock
  await subscriptions.blockSubscriber.start()
  LocalSubscription(subscriptions: subscriptions, id: id)

proc subscribe*(
  subscriptions: Subscriptions,
  filter: EventFilter,
  onLog: LogHandler
): Future[Subscription] {.async:(raises:[ProviderError, CancelledError]).} =
  let id = subscriptions.nextSubscriptionId
  inc subscriptions.nextSubscriptionId
  subscriptions.logSubscriptions[id] = (filter, onLog)
  await subscriptions.blockSubscriber.start()
  LocalSubscription(subscriptions: subscriptions, id: id)

method unsubscribe*(
  subscription: LocalSubscription
) {.async:(raises:[ProviderError, CancelledError]).} =
  let subscriptions = subscription.subscriptions
  let id = subscription.id
  subscriptions.logSubscriptions.del(id)
  subscriptions.blockSubscriptions.del(id)
  if subscriptions.len == 0:
    await subscriptions.blockSubscriber.stop()

proc getLogs(
  subscriptions: Subscriptions,
  filter: EventFilter,
  blockTag: BlockTag
): Future[seq[Log]] {.async:(raises:[ProviderError, CancelledError]).} =
  let logFilter = Filter()
  logFilter.address = filter.address
  logFilter.topics = filter.topics
  logFilter.fromBlock = blockTag
  logFilter.toBlock = blockTag
  await subscriptions.provider.getLogs(logFilter)

proc getLogs(
  subscriptions: Subscriptions,
  blck: Block
): Future[Table[SubscriptionId, seq[Log]]] {.
  async:(raises:[ProviderError, CancelledError])
.} =
  without blockNumber =? blck.number:
    return
  let blockTag = BlockTag.init(blockNumber)
  let ids = toSeq(subscriptions.logSubscriptions.keys)
  for id in ids:
    without (filter, _) =? subscriptions.logSubscriptions.?[id]:
      continue
    if filter notin blck:
      continue
    result[id] = await subscriptions.getLogs(filter, blockTag)

proc processBlock(
  subscriptions: Subscriptions,
  blockNumber: BlockNumber
): Future[bool] {.async:(raises:[CancelledError]).} =
  try:
    let blockTag = BlockTag.init(blockNumber)
    without blck =? await subscriptions.provider.getBlock(blockTag):
      return false
    if blck.logsBloom.isNone:
      return false
    let logs = await subscriptions.getLogs(blck)
    for handler in subscriptions.blockSubscriptions.values:
      handler(blck)
    for (id, logs) in logs.pairs:
      if (_, handler) =? subscriptions.logSubscriptions.?[id]:
        for log in logs:
          handler(log)
    return true
  except ProviderError:
    return false

func new*(
  _: type Subscriptions,
  provider: Provider,
  pollingInterval: Duration
): Subscriptions =
  let subscriptions = Subscriptions()
  proc processBlock(
    blockNumber: BlockNumber
  ): Future[bool] {.async:(raises:[CancelledError]).} =
    await subscriptions.processBlock(blockNumber)
  let blockSubscriber = BlockSubscriber.new(
    provider,
    processBlock,
    pollingInterval
  )
  subscriptions.provider = provider
  subscriptions.blockSubscriber = blockSubscriber
  subscriptions

proc close*(subscriptions: Subscriptions) {.async:(raises:[]).} =
  await subscriptions.blockSubscriber.stop()

proc update*(subscriptions: Subscriptions) =
  subscriptions.blockSubscriber.update()
