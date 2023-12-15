import std/tables
import std/sequtils
import pkg/chronos
import pkg/json_rpc/rpcclient
import ../../basics
import ../../provider
import ./rpccalls
import ./conversions
import ./looping

type
  JsonRpcSubscriptions* = ref object of RootObj
    client: RpcClient
    callbacks: Table[JsonNode, SubscriptionCallback]
  SubscriptionCallback = proc(id, arguments: JsonNode) {.gcsafe, raises:[].}

# FIXME Nim 1.6.XX seems to have issues tracking exception effects and will see
#   ghost unlisted Exceptions with table operations. In a smaller example
#   (https://forum.nim-lang.org/t/10749), using {.experimental:"strictEffects".}
#   would fix it, but it doesn't work here for some reason I yet don't
#   understand. For now, therefore, I'm simply using a mitigation which is to
#   tell the compiler the truth.
template mitigateEffectsBug(body) = {.cast(raises: []).}: body

method subscribeBlocks*(subscriptions: JsonRpcSubscriptions,
                        onBlock: BlockHandler):
                       Future[JsonNode]
                       {.async, base.} =
  raiseAssert "not implemented"

method subscribeLogs*(subscriptions: JsonRpcSubscriptions,
                      filter: EventFilter,
                      onLog: LogHandler):
                     Future[JsonNode]
                     {.async, base.} =
  raiseAssert "not implemented"

method unsubscribe*(subscriptions: JsonRpcSubscriptions,
                    id: JsonNode)
                   {.async, base.} =
  raiseAssert "not implemented"

method close*(subscriptions: JsonRpcSubscriptions) {.async, base.} =
  let ids = toSeq subscriptions.callbacks.keys
  for id in ids:
    await subscriptions.unsubscribe(id)

proc getCallback(subscriptions: JsonRpcSubscriptions,
                 id: JsonNode): ?SubscriptionCallback =
  try:
    if subscriptions.callbacks.hasKey(id):
      subscriptions.callbacks[id].some
    else:
      SubscriptionCallback.none
  except Exception:
    SubscriptionCallback.none

# Web sockets

type
  WebSocketSubscriptions = ref object of JsonRpcSubscriptions

proc new*(_: type JsonRpcSubscriptions,
          client: RpcWebSocketClient): JsonRpcSubscriptions =
  let subscriptions = WebSocketSubscriptions(client: client)
  proc subscriptionHandler(arguments: JsonNode) {.raises:[].} =
    if id =? arguments["subscription"].catch and
       callback =? subscriptions.getCallback(id):
      callback(id, arguments)
  client.setMethodHandler("eth_subscription", subscriptionHandler)
  subscriptions

method subscribeBlocks(subscriptions: WebSocketSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonNode]
                      {.async.} =
  proc callback(id, arguments: JsonNode) =
    if blck =? Block.fromJson(arguments["result"]).catch:
      onBlock(blck)
  let id = await subscriptions.client.eth_subscribe("newHeads")
  mitigateEffectsBug: subscriptions.callbacks[id] = callback
  return id

method subscribeLogs(subscriptions: WebSocketSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async.} =
  proc callback(id, arguments: JsonNode) =
    if log =? Log.fromJson(arguments["result"]).catch:
      onLog(log)
  let id = await subscriptions.client.eth_subscribe("logs", filter)
  mitigateEffectsBug: subscriptions.callbacks[id] = callback
  return id

method unsubscribe(subscriptions: WebSocketSubscriptions,
                   id: JsonNode)
                  {.async.} =
  mitigateEffectsBug: subscriptions.callbacks.del(id)
  discard await subscriptions.client.eth_unsubscribe(id)

# Polling

type
  PollingSubscriptions = ref object of JsonRpcSubscriptions
    polling: Future[void]

proc new*(_: type JsonRpcSubscriptions,
          client: RpcHttpClient,
          pollingInterval = 4.seconds): JsonRpcSubscriptions =

  let subscriptions = PollingSubscriptions(client: client)

  proc getChanges(id: JsonNode): Future[JsonNode] {.async.} =
    try:
      return await subscriptions.client.eth_getFilterChanges(id)
    except CatchableError:
      return newJArray()

  proc poll(id: JsonNode) {.async.} =
    for change in await getChanges(id):
      if callback =? subscriptions.getCallback(id):
        callback(id, change)

  proc poll {.async.} =
    untilCancelled:
      for id in toSeq subscriptions.callbacks.keys:
        await poll(id)
      await sleepAsync(pollingInterval)

  subscriptions.polling = poll()
  subscriptions

method close*(subscriptions: PollingSubscriptions) {.async.} =
  await subscriptions.polling.cancelAndWait()
  await procCall JsonRpcSubscriptions(subscriptions).close()

method subscribeBlocks(subscriptions: PollingSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonNode]
                      {.async.} =

  proc getBlock(hash: BlockHash) {.async.} =
    try:
      if blck =? (await subscriptions.client.eth_getBlockByHash(hash, false)):
        onBlock(blck)
    except CatchableError:
      discard

  proc callback(id, change: JsonNode) =
    if hash =? BlockHash.fromJson(change).catch:
      asyncSpawn getBlock(hash)

  let id = await subscriptions.client.eth_newBlockFilter()
  mitigateEffectsBug: subscriptions.callbacks[id] = callback
  return id

method subscribeLogs(subscriptions: PollingSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async.} =

  proc callback(id, change: JsonNode) =
    if log =? Log.fromJson(change).catch:
      onLog(log)

  let id = await subscriptions.client.eth_newFilter(filter)
  mitigateEffectsBug: subscriptions.callbacks[id] = callback
  return id

method unsubscribe(subscriptions: PollingSubscriptions,
                   id: JsonNode)
                  {.async.} =
  mitigateEffectsBug: subscriptions.callbacks.del(id)
  discard await subscriptions.client.eth_uninstallFilter(id)
