import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for desktop hosts to connect to relay server
class RelayClient {
  WebSocketChannel? _channel;
  String? _roomId;
  String? _username;
  String? _deviceName;
  StreamSubscription? _streamSubscription;
  final String relayUrl;
  
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  
  bool get isConnected => _channel != null;
  String? get roomId => _roomId;
  String? get username => _username;
  String? get deviceName => _deviceName;
  
  RelayClient({required this.relayUrl});
  
  /// Get device name (hostname)
  static String getDeviceName() {
    try {
      return Platform.localHostname;
    } catch (e) {
      return 'Unknown Device';
    }
  }
  
  /// Register this device as a host with random room ID (legacy)
  Future<String> registerAsHost() async {
    try {
      debugPrint('Connecting to relay server: $relayUrl');
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      // Send register message
      _channel!.sink.add(jsonEncode({'type': 'register'}));
      debugPrint('Sent register message to relay');
      
      return await _waitForRegistration();
    } catch (e) {
      debugPrint('Failed to register as host: $e');
      rethrow;
    }
  }
  
  /// Register this device as a host with username (new method)
  Future<String> registerWithUsername(String username, {String? customDeviceName}) async {
    try {
      debugPrint('Connecting to relay server: $relayUrl');
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      _username = username;
      _deviceName = customDeviceName ?? getDeviceName();
      
      // Send register-username message
      _channel!.sink.add(jsonEncode({
        'type': 'register-username',
        'username': username,
        'deviceName': _deviceName,
      }));
      
      debugPrint('Sent register-username message: $username / $_deviceName');
      
      return await _waitForRegistration();
    } catch (e) {
      debugPrint('Failed to register with username: $e');
      rethrow;
    }
  }
  
  Future<String> _waitForRegistration() async {
    final completer = Completer<String>();
    
    _streamSubscription = _channel!.stream.listen(
      (message) {
        debugPrint('Received message from relay: $message');
        final msg = jsonDecode(message) as Map<String, dynamic>;
        
        if (msg['type'] == 'registered') {
          _roomId = msg['roomId'] as String;
          if (msg['username'] != null) {
            _username = msg['username'] as String;
          }
          if (msg['deviceName'] != null) {
            _deviceName = msg['deviceName'] as String;
          }
          debugPrint('Registered with room ID: $_roomId');
          if (!completer.isCompleted) {
            completer.complete(_roomId!);
          }
        } else if (msg['type'] == 'error') {
          debugPrint('Registration error: ${msg['message']}');
          if (!completer.isCompleted) {
            completer.completeError(Exception(msg['message']));
          }
        } else if (msg['type'] == 'ping') {
          // Respond to ping to keep connection alive
          _channel?.sink.add(jsonEncode({'type': 'pong'}));
        } else {
          // Forward other messages to listeners
          _messageController.add(msg);
        }
      },
      onError: (error, stackTrace) {
        debugPrint('❌ Relay WebSocket error: $error');
        debugPrint('Stack trace: $stackTrace');
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        debugPrint('⚠️ Relay WebSocket onDone called - connection closed!');
        debugPrint('Room ID was: $_roomId');
        _channel = null;
        _roomId = null;
      },
      cancelOnError: false,
    );
    
    final roomId = await completer.future;
    await Future.delayed(const Duration(milliseconds: 500));
    return roomId;
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
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _channel?.sink.close();
    _channel = null;
    _roomId = null;
    _username = null;
    _deviceName = null;
    debugPrint('Disconnected from relay server');
  }
  
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
