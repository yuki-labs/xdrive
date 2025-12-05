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
  
  // 2MB chunks - optimized for faster seeking while maintaining mobile compatibility
  static const int chunkSize = 2 * 1024 * 1024; // 2MB
  
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
      
      final response = await relayConnection.sendRequest(requestData);
      final responseData = utf8.decode(base64.decode(response));
      
      // Decrypt if encryption key is available
      final decryptedData = encryptionKey != null
          ? EncryptionService.decryptString(responseData, encryptionKey!)
          : responseData;
      
      if (decryptedData == null) {
        debugPrint('Failed to decrypt file info');
        return null;
      }
      
      final jsonData = jsonDecode(decryptedData);
      debugPrint('File info: size=${jsonData['size']}, mimeType=${jsonData['mimeType']}');
      
      return jsonData;
    } catch (e) {
      debugPrint('Error getting file info: $e');
      return null;
    }
  }
  
  /// Fetch a specific chunk with headers
  Future<Map<String, dynamic>?> fetchChunkWithHeaders(int start, int end) async {
    try {
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\nRange: bytes=$start-$end\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching chunk: bytes=$start-$end for $filePath');
      
      final response = await relayConnection.sendRequest(requestData);
      
      // Response is base64 encoded bytes
      final chunkData = base64.decode(response);
      
      debugPrint('Received chunk: ${chunkData.length} bytes');
      
      return {
        'data': Uint8List.fromList(chunkData),
        'start': start,
        'end': start + chunkData.length - 1,
      };
    } catch (e) {
      debugPrint('Error fetching chunk: $e');
      return null;
    }
  }
  
  /// Stream file progressively
  Future<void> fetchProgressive({
    required Function(Uint8List chunk, int offset) onChunk,
    required Function() onComplete,
    required Function(dynamic error) onError,
  }) async {
    try {
      int offset = 0;
      
      while (true) {
        final end = offset + chunkSize - 1;
        final result = await fetchChunkWithHeaders(offset, end);
        
        if (result == null || result['data'] == null) {
          onComplete();
          return;
        }
        
        final chunk = result['data'] as Uint8List;
        onChunk(chunk, offset);
        
        // If chunk is smaller than requested, we've reached the end
        if (chunk.length < chunkSize) {
          onComplete();
          return;
        }
        
        offset += chunk.length;
      }
    } catch (e) {
      onError(e);
    }
  }
}
