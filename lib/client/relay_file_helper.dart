import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../relay/relay_connection.dart';
import '../crypto/encryption_service.dart';

/// Helper for relay-specific file operations
class RelayFileHelper {
  final RelayConnection? Function() _getRelayConnection;
  final Uint8List? Function() _getEncryptionKey;
  
  // Thumbnail cache
  final Map<String, Uint8List> _thumbnailCache = {};
  
  RelayFileHelper({
    required RelayConnection? Function() getRelayConnection,
    required Uint8List? Function() getEncryptionKey,
  })  : _getRelayConnection = getRelayConnection,
        _getEncryptionKey = getEncryptionKey;
  
  /// Fetch thumbnail bytes via relay
  Future<Uint8List?> getThumbnailBytes(String filePath) async {
    // Check cache
    if (_thumbnailCache.containsKey(filePath)) {
      return _thumbnailCache[filePath];
    }
    
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /thumbnail?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final thumbnailBytes = base64.decode(responseData);
      
      _thumbnailCache[filePath] = thumbnailBytes;
      return thumbnailBytes;
    } catch (e) {
      debugPrint('Error fetching thumbnail via relay: $e');
      return null;
    }
  }
  
  /// Fetch full file bytes via relay (for images)
  Future<Uint8List?> getStreamBytes(String filePath) async {
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final fileBytes = base64.decode(responseData);
      
      debugPrint('Received file via relay: ${fileBytes.length} bytes');
      return fileBytes;
    } catch (e) {
      debugPrint('Error fetching file via relay: $e');
      return null;
    }
  }
  
  /// Generic HTTP request via relay
  Future<String?> httpViaRelay(String method, String path) async {
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = '$method $path HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      final encryptionKey = _getEncryptionKey();
      if (encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(bodyText, encryptionKey);
        if (decrypted == null) {
          debugPrint('Failed to decrypt relay response for $path');
          return null;
        }
        bodyText = decrypted;
      }
      
      return bodyText;
    } catch (e) {
      debugPrint('Error in HTTP via relay: $e');
      return null;
    }
  }
  
  /// Fetch files list via relay
  Future<String?> fetchFilesViaRelay(String path) async {
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /files?path=${Uri.encodeComponent(path)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      final encryptionKey = _getEncryptionKey();
      if (encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(bodyText, encryptionKey);
        if (decrypted == null) {
          debugPrint('Failed to decrypt relay response');
          return null;
        }
        bodyText = decrypted;
      }
      
      return bodyText;
    } catch (e) {
      debugPrint('Error fetching via relay: $e');
      return null;
    }
  }
}
