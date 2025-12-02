import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../relay/streaming_proxy_server.dart';
import '../relay/relay_connection.dart';

/// Manages the local proxy server for video streaming
class ProxyManager {
  StreamingProxyServer? _proxyServer;
  
  final RelayConnection? Function() _getRelayConnection;
  final bool Function() _isUsingRelay;
  final Uint8List? Function() _getEncryptionKey;
  
  ProxyManager({
    required RelayConnection? Function() getRelayConnection,
    required bool Function() isUsingRelay,
    required Uint8List? Function() getEncryptionKey,
  })  : _getRelayConnection = getRelayConnection,
        _isUsingRelay = isUsingRelay,
        _getEncryptionKey = getEncryptionKey;
  
  /// Start streaming proxy server
  Future<void> startProxyServer() async {
    if (_proxyServer != null) return; // Already running
    if (!_isUsingRelay()) return; // Only for relay mode
    
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) {
      debugPrint('Cannot start proxy: no relay connection');
      return;
    }
    
    try {
      _proxyServer = StreamingProxyServer(
        relayConnection: relayConnection,
        encryptionKey: _getEncryptionKey(),
      );
      final baseUrl = await _proxyServer!.start();
      debugPrint('Streaming proxy started: $baseUrl');
    } catch (e) {
      debugPrint('Failed to start proxy: $e');
    }
  }
  
  /// Stop proxy server
  Future<void> stopProxyServer() async {
    if (_proxyServer != null) {
      await _proxyServer!.stop();
      _proxyServer = null;
    }
  }
  
  /// Get proxy URL for file
  String? getProxyUrl(String filePath) {
    return _proxyServer?.getProxyUrl(filePath);
  }
}
