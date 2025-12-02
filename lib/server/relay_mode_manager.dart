import 'package:flutter/foundation.dart';
import '../relay/relay_client.dart';
import 'relay_request_handler.dart';

/// Manages relay mode state and connections
class RelayModeManager {
  RelayClient? _relayClient;
  bool _relayMode = false;
  
  bool get relayMode => _relayMode;
  String? get relayRoomId => _relayClient?.roomId;
  RelayClient? get relayClient => _relayClient;
  
  /// Enable relay mode and setup message handling
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
      return roomId;
    } catch (e) {
      debugPrint('Failed to enable relay mode: $e');
      _relayClient = null;
      rethrow;
    }
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
