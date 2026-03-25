enum ConnectionStatus { connected, reconnecting }

class HeartbeatManager {
  void start(void Function(ConnectionStatus status) onStatus) {
    onStatus(ConnectionStatus.connected);
  }

  void markReconnecting() {}

  void stop() {}
}
