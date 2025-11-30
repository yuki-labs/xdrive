import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../crypto/encryption_service.dart';
import '../relay/relay_connection.dart';

/// Helper methods for relay operations
class RelayHelper {
  final RelayConnection? relayConnection;
  final Uint8List? encryptionKey;
  
  RelayHelper({
    this.relayConnection,
    this.encryptionKey,
  });
  
  /// Generic HTTP request via relay
  Future<String?> httpViaRelay(String method, String path) async {
    if (relayConnection == null) {
      return null;
    }
    
    try {
      // Build HTTP request
      final requestLine = '$method $path HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Sending $method via relay: $path');
      
      // Send through relay
      final responseData = await relayConnection!.sendRequest(requestData);
      
      // Decode response
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      // Decrypt if needed
      if (encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(bodyText, encryptionKey!);
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
  
  /// Get thumbnail bytes via relay
  Future<Uint8List?> getThumbnailBytes(String filePath) async {
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /thumbnail?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching thumbnail via relay: $filePath');
      
      final responseData = await relayConnection!.sendRequest(requestData);
      final thumbnailBytes = base64.decode(responseData);
      
      return thumbnailBytes;
    } catch (e) {
      debugPrint('Error fetching thumbnail via relay: $e');
      return null;
    }
  }
  
  /// Get full file bytes via relay
  Future<Uint8List?> getStreamBytes(String filePath) async {
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching file via relay: $filePath');
      
      final responseData = await relayConnection!.sendRequest(requestData);
      final fileBytes = base64.decode(responseData);
      
      debugPrint('Received file via relay: ${fileBytes.length} bytes');
      
      return fileBytes;
    } catch (e) {
      debugPrint('Error fetching file via relay: $e');
      return null;
    }
  }
}
