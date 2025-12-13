import ../basics
import ../provider

type
  BlockSubscriber* = ref object
    provider: Provider
    processor: ProcessBlock
    pollingInterval: Duration
    lastSeen: BlockNumber
    lastProcessed: BlockNumber
    wake: AsyncEvent
    looping: Future[void].Raising([])
  ProcessBlock* =
    proc(number: BlockNumber): Future[bool] {.async:(raises:[CancelledError]).}

func new*(
  _: type BlockSubscriber,
  provider: Provider,
  processor: ProcessBlock,
  pollingInterval: Duration
): BlockSubscriber =
  BlockSubscriber(
    provider: provider,
    processor: processor,
    pollingInterval: pollingInterval,
    wake: newAsyncEvent()
  )

proc sleep(subscriber: BlockSubscriber) {.async:(raises:[CancelledError]).} =
  discard await subscriber.wake.wait().withTimeout(subscriber.pollingInterval)
  subscriber.wake.clear()

proc loop(subscriber: BlockSubscriber) {.async:(raises:[]).} =
  try:
    while true:
      try:
        await subscriber.sleep()
        subscriber.lastSeen = await subscriber.provider.getBlockNumber()
        for number in (subscriber.lastProcessed + 1)..subscriber.lastSeen:
          if await subscriber.processor(number):
            subscriber.lastProcessed = number
          else:
            break
      except ProviderError:
        discard
  except CancelledError:
    discard

proc start*(
  subscriber: BlockSubscriber
) {.async:(raises:[ProviderError, CancelledError]).} =
  if subscriber.looping.isNil:
    subscriber.lastSeen = await subscriber.provider.getBlockNumber()
    subscriber.lastProcessed = subscriber.lastSeen
    subscriber.wake.clear()
    subscriber.looping = subscriber.loop()

proc stop*(subscriber: BlockSubscriber) {.async:(raises:[]).} =
  if looping =? subscriber.looping:
    subscriber.looping = nil
    await looping.cancelAndWait()

proc update*(subscriber: BlockSubscriber) =
  subscriber.wake.fire()
