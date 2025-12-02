import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'relay_connection.dart';

/// Fetches file chunks via relay with proper header parsing
class ChunkedRelayFetcher {
  final RelayConnection relayConnection;
  final String filePath;
  
  static const int chunkSize = 512 * 1024; // 512KB
  
  ChunkedRelayFetcher({
    required this.relayConnection,
    required this.filePath,
  });
  
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
      
      // Parse HTTP response to extract headers and body
      final responseText = utf8.decode(responseBytes, allowMalformed: true);
      final parts = responseText.split('\r\n\r\n');
      
      if (parts.length < 2) {
        // Binary response without headers, just return data
        debugPrint('Received chunk: ${responseBytes.length} bytes');
        return {
          'data': responseBytes,
          'contentRange': null,
        };
      }
      
      // Parse headers
      final headerLines = parts[0].split('\r\n');
      String? contentRange;
      
      for (final line in headerLines) {
        final lower = line.toLowerCase();
        if (lower.startsWith('content-range:')) {
          contentRange = line.substring(line.indexOf(':') + 1).trim();
          debugPrint('Content-Range: $contentRange');
        }
      }
      
      // Body is everything after headers
      final bodyStart = responseText.indexOf('\r\n\r\n') + 4;
      final body = responseBytes.sublist(bodyStart);
      
      debugPrint('Received chunk: ${body.length} bytes');
      
      return {
        'data': body,
        'contentRange': contentRange,
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
