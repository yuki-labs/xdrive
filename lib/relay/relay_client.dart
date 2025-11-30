import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'room_id_generator.dart';

/// WebSocket client for desktop hosts to connect to relay server
class RelayClient {
  WebSocketChannel? _channel;
  String? _roomId;
  final String relayUrl;
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  bool get isConnected => _channel != null;
  String? get roomId => _roomId;
  
  RelayClient({required this.relayUrl});
  
  /// Register this device as a host and get a room ID
  Future<String> registerAsHost() async {
    try {
      debugPrint('Connecting to relay server: $relayUrl');
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      // Send register message
      _channel!.sink.add(jsonEncode({'type': 'register'}));
      debugPrint('Sent register message to relay');
      
      // Listen for response
      final completer = Completer<String>();
      
      _channel!.stream.listen(
        (message) {
          debugPrint('Received message from relay: $message');
          final msg = jsonDecode(message) as Map<String, dynamic>;
          
          if (msg['type'] == 'registered') {
            _roomId = msg['roomId'] as String;
            debugPrint('Registered with room ID: $_roomId');
            if (!completer.isCompleted) {
              completer.complete(_roomId!);
            }
          } else {
            // Forward other messages to listeners
            _messageController.add(msg);
          }
        },
        onError: (error) {
          debugPrint('Relay WebSocket error: $error');
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        onDone: () {
          debugPrint('Relay WebSocket closed');
          _channel = null;
          _roomId = null;
        },
      );
      
      return completer.future;
    } catch (e) {
      debugPrint('Failed to register as host: $e');
      rethrow;
    }
  }
  
  /// Send a response back through the relay
  void sendResponse(String requestId, String data) {
    if (_channel == null) {
      debugPrint('Cannot send response - not connected to relay');
      return;
    }
    
    final message = jsonEncode({
      'type': 'response',
      'requestId': requestId,
      'data': data,
    });
    
    _channel!.sink.add(message);
    debugPrint('Sent response for request $requestId');
  }
  
  /// Disconnect from relay server
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _roomId = null;
    debugPrint('Disconnected from relay server');
  }
  
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
