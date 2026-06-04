import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';

void main() {
  test('PC Server WebSocket Handshake Test', () async {
    // This test expects the PC server to be running on localhost:8080
    // In a real CI environment, we would mock the server or use a local one.
    
    final socket = await WebSocket.connect('ws://localhost:8080');
    
    // Expect handshake from server
    socket.listen((data) {
      final message = jsonDecode(data);
      expect(message['type'], 'handshake');
      expect(message['message'], 'Connected to PC');
      socket.close();
    });
  });
}
