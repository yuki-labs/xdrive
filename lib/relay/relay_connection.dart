import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

/// WebSocket connection for mobile clients to join relay rooms
class RelayConnection {
  WebSocketChannel? _channel;
  final String relayUrl;
  String? _roomId;
  
  final Map<String, Completer<String>> _pendingRequests = {};
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  bool get isConnected => _channel != null;
  String? get roomId => _roomId;
  
  RelayConnection({required this.relayUrl});
  
  /// Join a relay room using room ID
  Future<void> joinRoom(String roomId) async {
    try {
      debugPrint('Connecting to relay server: $relayUrl');
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      _roomId = roomId;
      
      // Send join message
      _channel!.sink.add(jsonEncode({
        'type': 'join',
        'roomId': roomId,
      }));
      debugPrint('Sent join message for room: $roomId');
      
      // Listen for messages
      _channel!.stream.listen(
        (message) {
          debugPrint('Received message from relay: $message');
          final msg = jsonDecode(message) as Map<String, dynamic>;
          
          if (msg['type'] == 'response') {
            // Handle response to our request
            final requestId = msg['requestId'] as String;
            final data = msg['data'] as String;
            
            if (_pendingRequests.containsKey(requestId)) {
              _pendingRequests[requestId]!.complete(data);
              _pendingRequests.remove(requestId);
            }
          } else {
            // Forward other messages to listeners
            _messageController.add(msg);
          }
        },
        onError: (error) {
          debugPrint('Relay WebSocket error: $error');
          // Complete all pending requests with error
          for (var completer in _pendingRequests.values) {
            completer.completeError(error);
          }
          _pendingRequests.clear();
        },
        onDone: () {
          debugPrint('Relay WebSocket closed');
          _channel = null;
          _roomId = null;
        },
      );
      
      // Wait a moment for connection to establish
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      debugPrint('Failed to join room: $e');
      rethrow;
    }
  }
  
  /// Send request through relay and wait for response
  Future<String> sendRequest(String data) async {
    if (_channel == null) {
      throw Exception('Not connected to relay');
    }
    
    final requestId = const Uuid().v4();
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;
    
    final message = jsonEncode({
      'type': 'request',
      'requestId': requestId,
      'data': data,
    });
    
    _channel!.sink.add(message);
    debugPrint('Sent request $requestId');
    
    // Set timeout
    Future.delayed(const Duration(seconds: 30), () {
      if (_pendingRequests.containsKey(requestId)) {
        _pendingRequests[requestId]!.completeError(
          TimeoutException('Request timed out', const Duration(seconds: 30))
        );
        _pendingRequests.remove(requestId);
      }
    });
    
    return completer.future;
  }
  
  /// Disconnect from relay server
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _roomId = null;
    _pendingRequests.clear();
    debugPrint('Disconnected from relay server');
  }
  
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
