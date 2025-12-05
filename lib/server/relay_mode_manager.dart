import 'package:flutter/foundation.dart';
import '../relay/relay_client.dart';
import 'relay_request_handler.dart';

/// Manages relay mode state and connections
class RelayModeManager {
  RelayClient? _relayClient;
  bool _relayMode = false;
  
  bool get relayMode => _relayMode;
  String? get relayRoomId => _relayClient?.roomId;
  String? get relayUsername => _relayClient?.username;
  String? get relayDeviceName => _relayClient?.deviceName;
  RelayClient? get relayClient => _relayClient;
  
  /// Enable relay mode with random room ID (legacy)
  Future<String> enableRelayMode({
    required String relayUrl,
    required RelayRequestHandler requestHandler,
  }) async {
    if (_relayMode) {
      debugPrint('Relay mode already enabled');
      return _relayClient!.roomId!;
    }
    
    try {
      _relayClient = RelayClient(relayUrl: relayUrl);
      final roomId = await _relayClient!.registerAsHost();
      _relayMode = true;
      
      debugPrint('Relay mode enabled with room ID: $roomId');
      _setupMessageListener(requestHandler);
      
      return roomId;
    } catch (e) {
      debugPrint('Failed to enable relay mode: $e');
      _relayClient = null;
      rethrow;
    }
  }
  
  /// Enable relay mode with username (new method)
  Future<String> enableRelayModeWithUsername({
    required String relayUrl,
    required String username,
    required RelayRequestHandler requestHandler,
    String? customDeviceName,
  }) async {
    if (_relayMode) {
      debugPrint('Relay mode already enabled');
      return _relayClient!.roomId!;
    }
    
    try {
      _relayClient = RelayClient(relayUrl: relayUrl);
      final roomId = await _relayClient!.registerWithUsername(
        username,
        customDeviceName: customDeviceName,
      );
      _relayMode = true;
      
      debugPrint('Relay mode enabled for "$username" on "${_relayClient!.deviceName}"');
      _setupMessageListener(requestHandler);
      
      return roomId;
    } catch (e) {
      debugPrint('Failed to enable relay mode with username: $e');
      _relayClient = null;
      rethrow;
    }
  }
  
  void _setupMessageListener(RelayRequestHandler requestHandler) {
    debugPrint('Setting up relay message listener...');
    
    _relayClient!.messages.listen((message) {
      debugPrint('📩 Received relay message type: ${message['type']}');
      if (message['type'] == 'request') {
        debugPrint('🔥 Processing relay request...');
        requestHandler.handleRequest(message);
      } else {
        debugPrint('⚠️  Ignoring non-request message: ${message['type']}');
      }
    });
    
    debugPrint('✅ Relay message listener active');
  }
  
  /// Disable relay mode
  Future<void> disableRelayMode() async {
    if (_relayClient != null) {
      await _relayClient!.disconnect();
      _relayClient = null;
      _relayMode = false;
      debugPrint('Relay mode disabled');
    }
  }
}
