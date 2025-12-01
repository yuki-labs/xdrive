import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'relay_connection.dart';
import 'dart:convert';

/// Fetches file chunks via relay for streaming
class ChunkedRelayFetcher {
  final RelayConnection relayConnection;
  final String filePath;
  
  // Chunk size: 512KB per request
  static const int chunkSize = 512 * 1024;
  
  ChunkedRelayFetcher({
    required this.relayConnection,
    required this.filePath,
  });
  
  /// Fetch a specific chunk of the file
  Future<Uint8List?> fetchChunk(int start, int end) async {
    try {
      // Build HTTP range request
      final rangeHeader = 'bytes=$start-$end';
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n'
          'Range: $rangeHeader\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching chunk: $rangeHeader for $filePath');
      
      // Send through relay
      final responseData = await relayConnection.sendRequest(requestData);
      
      // Decode response - binary data
      final chunkBytes = base64.decode(responseData);
      
      debugPrint('Received chunk: ${chunkBytes.length} bytes');
      return chunkBytes;
    } catch (e) {
      debugPrint('Error fetching chunk: $e');
      return null;
    }
  }
  
  /// Get file size from server
  Future<int?> getFileSize() async {
    try {
      // Request first byte to get content-range with total size
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n'
          'Range: bytes=0-0\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      
      // Parse response headers (if relay sends them)
      // For now, just fetch first chunk and estimate
      // TODO: Parse actual content-range header from response
      
      return null; // Will be implemented when needed
    } catch (e) {
      debugPrint('Error getting file size: $e');
      return null;
    }
  }
  
  /// Fetch chunks progressively with callback
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
      
      // If chunk is smaller than requested, we've reached the end
      if (chunk.length < chunkSize) {
        hasMore = false;
      }
    }
    
    onComplete();
  }
}
