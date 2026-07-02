import 'package:atta/src/services/chat_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expected websocket close errors are treated as benign', () {
    expect(
      ChatSocketService.isExpectedSocketCloseError(
        _FakeWebSocketConnectionClosed(),
      ),
      isTrue,
    );
    expect(
      ChatSocketService.isExpectedSocketCloseError(
        Exception('Connection Closed'),
      ),
      isTrue,
    );
    expect(
      ChatSocketService.isExpectedSocketCloseError(
        Exception('socket timeout'),
      ),
      isFalse,
    );
  });
}

class _FakeWebSocketConnectionClosed implements Exception {
  @override
  String toString() => 'Connection Closed';
}
