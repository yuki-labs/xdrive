import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'relay_connection.dart';
import '../crypto/encryption_service.dart';

/// Fetches file chunks via relay with encryption support
class ChunkedRelayFetcher {
  final RelayConnection relayConnection;
  final String filePath;
  final Uint8List? encryptionKey;
  
  static const int chunkSize = 512 * 1024; // 512KB
  
  ChunkedRelayFetcher({
    required this.relayConnection,
    required this.filePath,
    this.encryptionKey,
  });
  
  /// Get file metadata (size, mimeType) via /file-info endpoint
  Future<Map<String, dynamic>?> getFileInfo() async {
    try {
      final requestLine = 'GET /file-info?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching file info for $filePath');
      
      final responseData = await relayConnection.sendRequest(requestData);
      final responseBytes = base64.decode(responseData);
      String responseText = utf8.decode(responseBytes);
      
      // Decrypt if encryption key is available
      if (encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(responseText, encryptionKey!);
        if (decrypted == null) {
          debugPrint('Failed to decrypt file info response');
          return null;
        }
        responseText = decrypted;
      }
      
      // Parse JSON response
      final fileInfo = jsonDecode(responseText) as Map<String, dynamic>;
      debugPrint('File info: size=${fileInfo['size']}, mimeType=${fileInfo['mimeType']}');
      
      return fileInfo;
    } catch (e) {
      debugPrint('Error fetching file info: $e');
      return null;
    }
  }
  
  /// Fetch chunk and return both data and headers
  Future<Map<String, dynamic>?> fetchChunkWithHeaders(int start, int end) async {
    try {
      final rangeHeader = 'bytes=$start-$end';
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n'
          'Range: $rangeHeader\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching chunk: $rangeHeader for $filePath');
      
      final responseData = await relayConnection.sendRequest(requestData);
      final responseBytes = base64.decode(responseData);
      
      // Response is just binary data (no HTTP headers from relay)
      debugPrint('Received chunk: ${responseBytes.length} bytes');
      
      return {
        'data': responseBytes,
        'contentRange': null,
      };
    } catch (e) {
      debugPrint('Error fetching chunk: $e');
      return null;
    }
  }
  
  /// Fetch chunk (backwards compatible)
  Future<Uint8List?> fetchChunk(int start, int end) async {
    final result = await fetchChunkWithHeaders(start, end);
    return result?['data'] as Uint8List?;
  }
  
  /// Fetch progressively
  Future<void> fetchProgressive({
    required Function(Uint8List chunk, int offset) onChunk,
    required Function() onComplete,
    required Function(String error) onError,
  }) async {
    int offset = 0;
    bool hasMore = true;
    
    while (hasMore) {
      final end = offset + chunkSize - 1;
      final chunk = await fetchChunk(offset, end);
      
      if (chunk == null || chunk.isEmpty) {
        hasMore = false;
        break;
      }
      
      onChunk(chunk, offset);
      offset += chunk.length;
      
      if (chunk.length < chunkSize) {
        hasMore = false;
      }
    }
    
    onComplete();
  }
}
