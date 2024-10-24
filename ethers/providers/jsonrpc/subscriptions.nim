import std/tables
import std/sequtils
import std/strutils
import pkg/chronos
import pkg/json_rpc/rpcclient
import ../../basics
import ../../provider
include ../../nimshims/hashes
import ./rpccalls
import ./conversions
import ./looping

type
  JsonRpcSubscriptions* = ref object of RootObj
    client: RpcClient
    callbacks: Table[JsonNode, SubscriptionCallback]
    methodHandlers: Table[string, MethodHandler]
  MethodHandler* = proc (j: JsonNode) {.gcsafe, raises: [].}
  SubscriptionCallback = proc(id, arguments: JsonNode) {.gcsafe, raises:[].}

{.push raises:[].}

template `or`(a: JsonNode, b: typed): JsonNode =
  if a.isNil: b else: a

func start*(subscriptions: JsonRpcSubscriptions) =
  subscriptions.client.onProcessMessage =
    proc(client: RpcClient,
         line: string): Result[bool, string] {.gcsafe, raises: [].} =
      if json =? JsonNode.fromJson(line):
        if "method" in json:
          let methodName = json{"method"}.getStr()
          if methodName in subscriptions.methodHandlers:
            let handler = subscriptions.methodHandlers.getOrDefault(methodName)
            if not handler.isNil:
              handler(json{"params"} or newJArray())
              # false = do not continue processing message using json_rpc's
              # default processing handler
              return ok false

      # true = continue processing message using json_rpc's default message handler
      return ok true


proc setMethodHandler(
  subscriptions: JsonRpcSubscriptions,
  `method`: string,
  handler: MethodHandler
) =
  subscriptions.methodHandlers[`method`] = handler

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
    if not id.isNil and id in subscriptions.callbacks:
      subscriptions.callbacks[id].some
    else:
      SubscriptionCallback.none
  except KeyError:
    SubscriptionCallback.none

# Web sockets

type
  WebSocketSubscriptions = ref object of JsonRpcSubscriptions

proc new*(_: type JsonRpcSubscriptions,
          client: RpcWebSocketClient): JsonRpcSubscriptions =

  let subscriptions = WebSocketSubscriptions(client: client)
  proc subscriptionHandler(arguments: JsonNode) {.raises:[].} =
    let id = arguments{"subscription"} or newJString("")
    if callback =? subscriptions.getCallback(id):
      callback(id, arguments)
  subscriptions.setMethodHandler("eth_subscription", subscriptionHandler)
  subscriptions

method subscribeBlocks(subscriptions: WebSocketSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonNode]
                      {.async.} =
  proc callback(id, arguments: JsonNode) {.raises: [].} =
    if blck =? Block.fromJson(arguments{"result"}):
      onBlock(blck)
  let id = await subscriptions.client.eth_subscribe("newHeads")
  subscriptions.callbacks[id] = callback
  return id

method subscribeLogs(subscriptions: WebSocketSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async.} =
  proc callback(id, arguments: JsonNode) =
    if log =? Log.fromJson(arguments{"result"}):
      onLog(log)
  let id = await subscriptions.client.eth_subscribe("logs", filter)
  subscriptions.callbacks[id] = callback
  return id

method unsubscribe*(subscriptions: WebSocketSubscriptions,
                   id: JsonNode)
                  {.async.} =
  subscriptions.callbacks.del(id)
  discard await subscriptions.client.eth_unsubscribe(id)

# Polling

type
  PollingSubscriptions = ref object of JsonRpcSubscriptions
    polling: Future[void]

    # We need to keep around the filters that are used to create log filters on the RPC node
    # as there might be a time when they need to be recreated as RPC node might prune/forget
    # about them
    filters: Table[JsonNode, EventFilter]

    # Used when filters are recreated to translate from the id that user
    # originally got returned to new filter id
    subscriptionMapping: Table[JsonNode, JsonNode]

proc new*(_: type JsonRpcSubscriptions,
          client: RpcHttpClient,
          pollingInterval = 4.seconds): JsonRpcSubscriptions =

  let subscriptions = PollingSubscriptions(client: client)

  proc getChanges(originalId: JsonNode): Future[JsonNode] {.async.} =
    try:
      let mappedId = subscriptions.subscriptionMapping[originalId]
      return await subscriptions.client.eth_getFilterChanges(mappedId)
    except CatchableError as e:
      if "filter not found" in e.msg:
        let filter = subscriptions.filters[originalId]
        let newId = await subscriptions.client.eth_newFilter(filter)
        subscriptions.subscriptionMapping[originalId] = newId

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
    if hash =? BlockHash.fromJson(change):
      asyncSpawn getBlock(hash)

  let id = await subscriptions.client.eth_newBlockFilter()
  subscriptions.callbacks[id] = callback
  subscriptions.subscriptionMapping[id] = id
  return id

method subscribeLogs(subscriptions: PollingSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async.} =

  proc callback(id, change: JsonNode) =
    if log =? Log.fromJson(change):
      onLog(log)

  let id = await subscriptions.client.eth_newFilter(filter)
  subscriptions.callbacks[id] = callback
  subscriptions.filters[id] = filter
  subscriptions.subscriptionMapping[id] = id
  return id

method unsubscribe*(subscriptions: PollingSubscriptions,
                   id: JsonNode)
                  {.async.} =
  discard await subscriptions.client.eth_uninstallFilter(subscriptions.subscriptionMapping[id])
  subscriptions.filters.del(id)
  subscriptions.callbacks.del(id)
  subscriptions.subscriptionMapping.del(id)
