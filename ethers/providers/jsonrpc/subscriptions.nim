import std/tables
import std/sequtils
import std/strutils
import pkg/chronos
import pkg/questionable
import pkg/json_rpc/rpcclient
import pkg/serde
import ../../basics
import ../../errors
import ../../provider
include ../../nimshims/hashes
import ./rpccalls
import ./conversions
import ./looping

export serde

type
  JsonRpcSubscriptions* = ref object of RootObj
    client: RpcClient
    callbacks: Table[JsonNode, SubscriptionCallback]
    methodHandlers: Table[string, MethodHandler]
  MethodHandler* = proc (j: JsonNode) {.gcsafe, raises: [].}
  SubscriptionCallback = proc(id: JsonNode, arguments: ?!JsonNode) {.gcsafe, raises:[].}

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
                       {.async, base, raises: [CancelledError].} =
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
                 id: JsonNode): ?SubscriptionCallback  {. raises:[].} =
  try:
    if not id.isNil and id in subscriptions.callbacks:
        try:
          return subscriptions.callbacks[id].some
        except: discard
    else:
      return SubscriptionCallback.none
  except KeyError:
    return SubscriptionCallback.none

# Web sockets

type
  WebSocketSubscriptions = ref object of JsonRpcSubscriptions

proc new*(_: type JsonRpcSubscriptions,
          client: RpcWebSocketClient): JsonRpcSubscriptions =

  let subscriptions = WebSocketSubscriptions(client: client)
  proc subscriptionHandler(arguments: JsonNode) {.raises:[].} =
    let id = arguments{"subscription"} or newJString("")
    if callback =? subscriptions.getCallback(id):
      callback(id, success(arguments))
  subscriptions.setMethodHandler("eth_subscription", subscriptionHandler)
  subscriptions

method subscribeBlocks(subscriptions: WebSocketSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonNode]
                      {.async, raises: [].} =
  proc callback(id: JsonNode, argumentsResult: ?!JsonNode) {.raises: [].} =
    without arguments =? argumentsResult, error:
        onBlock(failure(Block, error.toErr(SubscriptionError)))
        return

    if blck =? Block.fromJson(arguments{"result"}):
      onBlock(success(blck))

  let id = await subscriptions.client.eth_subscribe("newHeads")
  subscriptions.callbacks[id] = callback
  return id

method subscribeLogs(subscriptions: WebSocketSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async.} =
  proc callback(id: JsonNode, argumentsResult: ?!JsonNode) =
    without arguments =? argumentsResult, error:
      onLog(failure(Log, error.toErr(SubscriptionError)))
      return

    if log =? Log.fromJson(arguments{"result"}):
      onLog(success(log))

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
  PollingSubscriptions* = ref object of JsonRpcSubscriptions
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

  proc getChanges(originalId: JsonNode): Future[JsonNode] {.async, raises:[CancelledError, SubscriptionError].} =
    try:
      let mappedId = subscriptions.subscriptionMapping[originalId]
      let changes = await subscriptions.client.eth_getFilterChanges(mappedId)
      if changes.kind == JNull:
        return newJArray()
      elif changes.kind != JArray:
        raise newException(SubscriptionError,
          "HTTP polling: unexpected value returned from eth_getFilterChanges." &
          " Expected: JArray, got: " & $changes.kind)
      return changes
    except CancelledError as e:
      raise e
    except CatchableError as e:
      if "filter not found" in e.msg:
        let filter = subscriptions.filters[originalId]
        let newId = await subscriptions.client.eth_newFilter(filter)
        subscriptions.subscriptionMapping[originalId] = newId
        return await getChanges(originalId)
      else:
        raise newException(SubscriptionError, "HTTP polling: There was an exception while getting subscription changes: " & e.msg, e)

  proc poll(id: JsonNode) {.async: (raises: [CancelledError, SubscriptionError]).} =
    without callback =? subscriptions.getCallback(id):
        return

    try:
      for change in await getChanges(id):
        callback(id, success(change))
    except CancelledError as e:
          raise e
    except CatchableError as e:
      callback(id, failure(JsonNode, e))

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
                      {.async, raises:[CancelledError].} =

  proc getBlock(hash: BlockHash) {.async: (raises:[]).} =
    try:
      if blck =? (await subscriptions.client.eth_getBlockByHash(hash, false)):
        onBlock(success(blck))
    except CancelledError as e:
      discard
    except CatchableError as e:
      let wrappedErr = newException(SubscriptionError, "HTTP polling: There was an exception while getting subscription's block: " & e.msg, e)
      onBlock(failure(Block, wrappedErr))

  proc callback(id: JsonNode, changeResult: ?!JsonNode) {.raises:[].} =
    without change =? changeResult, error:
        onBlock(failure(Block, error.toErr(SubscriptionError)))
        return

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

  proc callback(id: JsonNode, changeResult: ?!JsonNode) =
    without change =? changeResult, error:
        onLog(failure(Log, error.toErr(SubscriptionError)))
        return

    if log =? Log.fromJson(change):
      onLog(success(log))

  let id = await subscriptions.client.eth_newFilter(filter)
  subscriptions.callbacks[id] = callback
  subscriptions.filters[id] = filter
  subscriptions.subscriptionMapping[id] = id
  return id

method unsubscribe*(subscriptions: PollingSubscriptions,
                   id: JsonNode)
                  {.async.} =
  subscriptions.filters.del(id)
  subscriptions.callbacks.del(id)
  let sub = subscriptions.subscriptionMapping[id]
  subscriptions.subscriptionMapping.del(id)
  try:
    discard await subscriptions.client.eth_uninstallFilter(sub)
  except CancelledError as e:
    raise e
  except CatchableError:
    # Ignore if uninstallation of the filter fails. If it's the last step in our
    # cleanup, then filter changes for this filter will no longer be polled so
    # if the filter continues to live on in geth for whatever reason then it
    # doesn't matter.
    discard
