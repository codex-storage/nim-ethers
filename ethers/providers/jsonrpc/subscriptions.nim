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
  JsonRpcSubscription = ref object of Subscription
    subscriptions: JsonRpcSubscriptions
    id: JsonNode
  SubscriptionCallback = proc(id, arguments: JsonNode) {.gcsafe, upraises:[].}

method subscribeBlocks*(subscriptions: JsonRpcSubscriptions,
                        onBlock: BlockHandler):
                       Future[JsonRpcSubscription]
                       {.async, base.} =
  raiseAssert "not implemented"

method subscribeLogs*(subscriptions: JsonRpcSubscriptions,
                      filter: Filter,
                      onLog: LogHandler):
                     Future[JsonRpcSubscription]
                     {.async, base.} =
  raiseAssert "not implemented"

method unsubscribe(subscriptions: JsonRpcSubscriptions,
                   id: JsonNode)
                  {.async, base.} =
  raiseAssert "not implemented"

method unsubscribe(subscription: JsonRpcSubscription) {.async.} =
  let subscriptions = subscription.subscriptions
  let id = subscription.id
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
  proc subscriptionHandler(arguments: JsonNode) {.upraises:[].} =
    if id =? arguments["subscription"].catch and
       callback =? subscriptions.getCallback(id):
      callback(id, arguments)
  client.setMethodHandler("eth_subscription", subscriptionHandler)
  subscriptions

method subscribeBlocks(subscriptions: WebSocketSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonRpcSubscription]
                      {.async.} =
  proc callback(id, arguments: JsonNode) =
    if blck =? Block.fromJson(arguments["result"]).catch:
      asyncSpawn onBlock(blck)
  let id = await subscriptions.client.eth_subscribe("newHeads")
  subscriptions.callbacks[id] = callback
  return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method subscribeLogs(subscriptions: WebSocketSubscriptions,
                     filter: Filter,
                     onLog: LogHandler):
                    Future[JsonRpcSubscription]
                    {.async.} =
  proc callback(id, arguments: JsonNode) =
    if log =? Log.fromJson(arguments["result"]).catch:
      onLog(log)
  let id = await subscriptions.client.eth_subscribe("logs", filter)
  subscriptions.callbacks[id] = callback
  return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method unsubscribe(subscriptions: WebSocketSubscriptions,
                   id: JsonNode)
                  {.async.} =
  subscriptions.callbacks.del(id)
  discard await subscriptions.client.eth_unsubscribe(id)

# Polling

type
  PollingSubscriptions = ref object of JsonRpcSubscriptions

proc new*(_: type JsonRpcSubscriptions,
          client: RpcHttpClient,
          pollingInterval = 4.seconds): JsonRpcSubscriptions =

  let subscriptions = PollingSubscriptions(client: client)

  proc poll(id: JsonNode) {.async.} =
    for change in await subscriptions.client.eth_getFilterChanges(id):
      if callback =? subscriptions.getCallback(id):
        callback(id, change)

  proc poll {.async.} =
    untilCancelled:
      for id in toSeq subscriptions.callbacks.keys:
        await poll(id)
      await sleepAsync(pollingInterval)

  asyncSpawn poll()

  subscriptions

method subscribeBlocks(subscriptions: PollingSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonRpcSubscription]
                      {.async.} =

  proc getBlock(hash: BlockHash) {.async.} =
    if blck =? (await subscriptions.client.eth_getBlockByHash(hash, false)):
      await onBlock(blck)

  proc callback(id, change: JsonNode) =
    if hash =? BlockHash.fromJson(change).catch:
      asyncSpawn getBlock(hash)

  let id = await subscriptions.client.eth_newBlockFilter()
  subscriptions.callbacks[id] = callback
  return JsonRpcSubscription(subscriptions: subscriptions, id: id)

method unsubscribe(subscriptions: PollingSubscriptions,
                   id: JsonNode)
                  {.async.} =
  subscriptions.callbacks.del(id)
  discard await subscriptions.client.eth_uninstallFilter(id)
