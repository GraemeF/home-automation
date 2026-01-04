import deep_heating/state.{type DeepHeatingState}

/// Messages that can be sent to the Lustre application.
pub type Msg {
  /// WebSocket connection established
  Connected
  /// WebSocket connection lost
  Disconnected
  /// Received new state from the server
  StateReceived(state: DeepHeatingState)
  /// User adjusted a room's temperature target
  AdjustRoom(room_name: String, delta: Float)
}
