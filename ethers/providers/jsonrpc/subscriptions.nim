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

export serde

type
  JsonRpcSubscriptions* = ref object of RootObj
    client: RpcClient
    callbacks: Table[JsonNode, SubscriptionCallback]
    methodHandlers: Table[string, MethodHandler]
  MethodHandler* = proc (j: JsonNode) {.gcsafe, raises: [].}
  SubscriptionCallback = proc(id: JsonNode, arguments: ?!JsonNode) {.gcsafe, raises:[].}

{.push raises:[].}

template convertErrorsToSubscriptionError(body) =
  try:
    body
  except CancelledError as error:
    raise error
  except CatchableError as error:
    raise error.toErr(SubscriptionError)

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
                       {.async: (raises: [SubscriptionError, CancelledError]), base,.} =
  raiseAssert "not implemented"

method subscribeLogs*(subscriptions: JsonRpcSubscriptions,
                      filter: EventFilter,
                      onLog: LogHandler):
                     Future[JsonNode]
                     {.async: (raises: [SubscriptionError, CancelledError]), base.} =
  raiseAssert "not implemented"

method unsubscribe*(subscriptions: JsonRpcSubscriptions,
                    id: JsonNode)
                   {.async: (raises: [CancelledError]), base.} =
  raiseAssert "not implemented "

method close*(subscriptions: JsonRpcSubscriptions) {.async: (raises: [SubscriptionError, CancelledError]), base.} =
  let ids = toSeq subscriptions.callbacks.keys
  for id in ids:
    await subscriptions.unsubscribe(id)

proc getCallback(subscriptions: JsonRpcSubscriptions,
                 id: JsonNode): ?SubscriptionCallback  {. raises:[].} =
  try:
    if not id.isNil and id in subscriptions.callbacks:
      return subscriptions.callbacks[id].some
  except: discard

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
                      {.async: (raises: [SubscriptionError, CancelledError]).} =
  proc callback(id: JsonNode, argumentsResult: ?!JsonNode) {.raises: [].} =
    without arguments =? argumentsResult, error:
      onBlock(failure(Block, error.toErr(SubscriptionError)))
      return

    let res = Block.fromJson(arguments{"result"}).mapFailure(SubscriptionError)
    onBlock(res)

  convertErrorsToSubscriptionError:
    let id = await subscriptions.client.eth_subscribe("newHeads")
    subscriptions.callbacks[id] = callback
    return id

method subscribeLogs(subscriptions: WebSocketSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async: (raises: [SubscriptionError, CancelledError]).} =
  proc callback(id: JsonNode, argumentsResult: ?!JsonNode) =
    without arguments =? argumentsResult, error:
      onLog(failure(Log, error.toErr(SubscriptionError)))
      return

    let res = Log.fromJson(arguments{"result"}).mapFailure(SubscriptionError)
    onLog(res)

  convertErrorsToSubscriptionError:
    let id = await subscriptions.client.eth_subscribe("logs", filter)
    subscriptions.callbacks[id] = callback
    return id

method unsubscribe*(subscriptions: WebSocketSubscriptions,
                   id: JsonNode)
                  {.async: (raises: [CancelledError]).} =
  try:
    subscriptions.callbacks.del(id)
    discard await subscriptions.client.eth_unsubscribe(id)
  except CancelledError as e:
    raise e
  except CatchableError:
    # Ignore if uninstallation of the subscribiton fails.
    discard

# Polling

type
  PollingSubscriptions* = ref object of JsonRpcSubscriptions
    polling: Future[void]

    # We need to keep around the filters that are used to create log filters on the RPC node
    # as there might be a time when they need to be recreated as RPC node might prune/forget
    # about them
    logFilters: Table[JsonNode, EventFilter]

    # Used when filters are recreated to translate from the id that user
    # originally got returned to new filter id
    subscriptionMapping: Table[JsonNode, JsonNode]

proc new*(_: type JsonRpcSubscriptions,
          client: RpcHttpClient,
          pollingInterval = 4.seconds): JsonRpcSubscriptions =

  let subscriptions = PollingSubscriptions(client: client)

  proc resubscribe(id: JsonNode): Future[?!void] {.async: (raises: [CancelledError]).} =
    try:
      var newId: JsonNode
      # Log filters are stored in logFilters, block filters are not persisted
      # there is they do not need any specific data for their recreation.
      # We use this to determine if the filter was log or block filter here.
      if subscriptions.logFilters.hasKey(id):
        let filter = subscriptions.logFilters[id]
        newId = await subscriptions.client.eth_newFilter(filter)
      else:
        newId = await subscriptions.client.eth_newBlockFilter()
      subscriptions.subscriptionMapping[id] = newId
    except CancelledError as e:
      raise e
    except CatchableError as e:
      return failure(void, e.toErr(SubscriptionError, "HTTP polling: There was an exception while getting subscription changes: " & e.msg))

    return success()

  proc getChanges(id: JsonNode): Future[?!JsonNode] {.async: (raises: [CancelledError]).} =
    if mappedId =? subscriptions.subscriptionMapping.?[id]:
      try:
        let changes = await subscriptions.client.eth_getFilterChanges(mappedId)
        if changes.kind == JArray:
          return success(changes)
      except JsonRpcError as e:
        if error =? (await resubscribe(id)).errorOption:
          return failure(JsonNode, error)

        # TODO: we could still miss some events between losing the subscription
        # and resubscribing. We should probably adopt a strategy like ethers.js,
        # whereby we keep track of the latest block number that we've seen
        # filter changes for:
        # https://github.com/ethers-io/ethers.js/blob/f97b92bbb1bde22fcc44100af78d7f31602863ab/packages/providers/src.ts/base-provider.ts#L977

        if not ("filter not found" in e.msg):
          return failure(JsonNode, e.toErr(SubscriptionError, "HTTP polling: There was an exception while getting subscription changes: " & e.msg))
      except CancelledError as e:
        raise e
      except SubscriptionError as e:
        return failure(JsonNode, e)
      except CatchableError as e:
        return failure(JsonNode, e.toErr(SubscriptionError, "HTTP polling: There was an exception while getting subscription changes: " & e.msg))
    return success(newJArray())

  proc poll(id: JsonNode) {.async: (raises: [CancelledError]).} =
    without callback =? subscriptions.getCallback(id):
      return

    without changes =? (await getChanges(id)), error:
      callback(id, failure(JsonNode, error))
      return

    for change in changes:
      callback(id, success(change))

  proc poll {.async: (raises: []).} =
    try:
      while true:
        for id in toSeq subscriptions.callbacks.keys:
          await poll(id)
        await sleepAsync(pollingInterval)
    except CancelledError:
      discard

  subscriptions.polling = poll()
  asyncSpawn subscriptions.polling
  subscriptions

method close*(subscriptions: PollingSubscriptions) {.async.} =
  await subscriptions.polling.cancelAndWait()
  await procCall JsonRpcSubscriptions(subscriptions).close()

method subscribeBlocks(subscriptions: PollingSubscriptions,
                       onBlock: BlockHandler):
                      Future[JsonNode]
                      {.async: (raises: [SubscriptionError, CancelledError]).} =

  proc getBlock(hash: BlockHash) {.async: (raises:[]).} =
    try:
      if blck =? (await subscriptions.client.eth_getBlockByHash(hash, false)):
        onBlock(success(blck))
    except CancelledError:
      discard
    except CatchableError as e:
      let error = e.toErr(SubscriptionError, "HTTP polling: There was an exception while getting subscription's block: " & e.msg)
      onBlock(failure(Block, error))

  proc callback(id: JsonNode, changeResult: ?!JsonNode) {.raises:[].} =
    without change =? changeResult, e:
      onBlock(failure(Block, e.toErr(SubscriptionError)))
      return

    if hash =? BlockHash.fromJson(change):
      asyncSpawn getBlock(hash)

  convertErrorsToSubscriptionError:
    let id = await subscriptions.client.eth_newBlockFilter()
    subscriptions.callbacks[id] = callback
    subscriptions.subscriptionMapping[id] = id
    return id

method subscribeLogs(subscriptions: PollingSubscriptions,
                     filter: EventFilter,
                     onLog: LogHandler):
                    Future[JsonNode]
                    {.async: (raises: [SubscriptionError, CancelledError]).} =

  proc callback(id: JsonNode, argumentsResult: ?!JsonNode) =
    without arguments =? argumentsResult, error:
      onLog(failure(Log, error.toErr(SubscriptionError)))
      return

    let res = Log.fromJson(arguments).mapFailure(SubscriptionError)
    onLog(res)

  convertErrorsToSubscriptionError:
    let id = await subscriptions.client.eth_newFilter(filter)
    subscriptions.callbacks[id] = callback
    subscriptions.logFilters[id] = filter
    subscriptions.subscriptionMapping[id] = id
    return id

method unsubscribe*(subscriptions: PollingSubscriptions,
                   id: JsonNode)
                  {.async: (raises: [CancelledError]).} =
  try:
    subscriptions.logFilters.del(id)
    subscriptions.callbacks.del(id)
    if sub =? subscriptions.subscriptionMapping.?[id]:
      subscriptions.subscriptionMapping.del(id)
      discard await subscriptions.client.eth_uninstallFilter(sub)
  except CancelledError as e:
    raise e
  except CatchableError:
    # Ignore if uninstallation of the filter fails. If it's the last step in our
    # cleanup, then filter changes for this filter will no longer be polled so
    # if the filter continues to live on in geth for whatever reason then it
    # doesn't matter.
    discard
