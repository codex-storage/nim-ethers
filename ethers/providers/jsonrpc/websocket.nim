import std/json
import pkg/json_rpc/rpcclient
import ../../basics
import ../../subscriptions
import ./rpccalls
import ./errors

proc useWebsocketUpdates*(
  subscriptions: Subscriptions,
  websocket: RpcWebSocketClient
) {.async:(raises:[JsonRpcProviderError, CancelledError]).} =
  var rpcSubscriptionId: JsonNode

  proc processMessage(client: RpcClient, message: string): Result[bool, string] =
    without message =? parseJson(message).catch:
      return ok true
    without rpcMethod =? message{"method"}:
      return ok true
    if rpcMethod.getStr() != "eth_subscription":
      return ok true
    without rpcParameter =? message{"params"}{"subscription"}:
      return ok true
    if rpcParameter != rpcSubscriptionId:
      return ok true

    subscriptions.update()

    ok false # do not process further using json-rpc default handler

  assert websocket.onProcessMessage.isNil
  websocket.onProcessMessage = processMessage

  convertError:
    rpcSubscriptionId = await websocket.eth_subscribe("newHeads")
