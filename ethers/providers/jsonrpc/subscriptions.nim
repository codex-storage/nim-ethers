import std/tables
import pkg/chronos
import pkg/json_rpc/rpcclient
import ../../basics
import ../../provider
import ./rpccalls
import ./conversions

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
  await subscription.subscriptions.unsubscribe(subscription.id)

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

proc new*(_: type JsonRpcSubscriptions,
          client: RpcWebSocketClient): JsonRpcSubscriptions =
  let subscriptions = WebSocketSubscriptions(client: client)
  proc subscriptionHandler(arguments: JsonNode) {.upraises:[].} =
    if id =? arguments["subscription"].catch and
       callback =? subscriptions.getCallback(id):
      callback(id, arguments)
  client.setMethodHandler("eth_subscription", subscriptionHandler)
  subscriptions

# Polling

type
  PollingSubscriptions = ref object of JsonRpcSubscriptions

func new*(_: type JsonRpcSubscriptions,
          client: RpcHttpClient): JsonRpcSubscriptions =
  PollingSubscriptions(client: client)
