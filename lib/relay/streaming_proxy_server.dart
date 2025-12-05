import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'chunked_relay_fetcher.dart';
import 'relay_connection.dart';

/// Local HTTP server that streams files through relay using chunks
class StreamingProxyServer {
  HttpServer? _server;
  int? _port;
  final RelayConnection relayConnection;
  final Uint8List? encryptionKey;
  
  // Cache file metadata
  int? _cachedFileSize;
  String? _cachedFilePath;
  String? _cachedMimeType;
  
  StreamingProxyServer({
    required this.relayConnection,
    this.encryptionKey,
  });
  
  Future<String?> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      
      debugPrint('Streaming proxy server started on localhost:$_port');
      
      _server!.listen((HttpRequest request) async {
        await _handleRequest(request);
      });
      
      return 'http://localhost:$_port';
    } catch (e) {
      debugPrint('Failed to start streaming proxy: $e');
      return null;
    }
  }
  
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.queryParameters['path'];
      
      debugPrint('📥 Proxy request: ${request.method} ${request.uri}');
      debugPrint('   Range: ${request.headers.value('range')}');
      
      if (path == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing path parameter');
        await request.response.close();
        return;
      }
      
      // Create chunked fetcher with encryption key
      final fetcher = ChunkedRelayFetcher(
        relayConnection: relayConnection,
        filePath: path,
        encryptionKey: encryptionKey,
      );
      
      // Get file metadata first
      await _getFileMetadata(fetcher, path);
      
      // Handle range requests
      final rangeHeader = request.headers.value('range');
      
      if (rangeHeader != null) {
        await _handleRangeRequest(request, fetcher, rangeHeader);
      } else {
        await _handleFullRequest(request, fetcher);
      }
    } catch (e) {
      debugPrint('❌ Error handling streaming request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
  
  /// Get and cache file metadata
  Future<void> _getFileMetadata(ChunkedRelayFetcher fetcher, String path) async {
    // Return if already cached
    if (_cachedFilePath == path && _cachedFileSize != null) {
      return;
    }
    
    try {
      final fileInfo = await fetcher.getFileInfo();
      
      if (fileInfo != null) {
        _cachedFileSize = fileInfo['size'] as int?;
        _cachedMimeType = fileInfo['mimeType'] as String?;
        _cachedFilePath = path;
        debugPrint('📊 File metadata: size=$_cachedFileSize, mime=$_cachedMimeType');
      }
    } catch (e) {
      debugPrint('⚠️ Error getting file metadata: $e');
    }
  }
  
  Future<void> _handleRangeRequest(
    HttpRequest request,
    ChunkedRelayFetcher fetcher,
    String rangeHeader,
  ) async {
    // Parse range: "bytes=0-1000"
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    
    if (match == null) {
      debugPrint('❌ Invalid range header: $rangeHeader');
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    
    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    
    // Calculate end position - MUST NOT exceed file size!
    int end;
    if (endStr != null && endStr.isNotEmpty) {
      end = int.parse(endStr);
    } else {
      // Open-ended range (bytes=X-): return one chunk or to EOF, whichever is smaller
      final requestedEnd = start + ChunkedRelayFetcher.chunkSize - 1;
      end = _cachedFileSize != null 
          ? requestedEnd.clamp(start, _cachedFileSize! - 1)
          : requestedEnd;
    }
    
    debugPrint('📍 Range request: bytes $start-$end');
    
    // Fetch the chunk
    final result = await fetcher.fetchChunkWithHeaders(start, end);
    
    if (result == null || result['data'] == null) {
      debugPrint('❌ Failed to fetch chunk');
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    final chunk = result['data'] as Uint8List;
    final actualEnd = start + chunk.length - 1;
    
    // CRITICAL: Must have file size for ExoPlayer
    if (_cachedFileSize == null) {
      debugPrint('⚠️ WARNING: No file size available!');
      // Fallback: return 200 OK without range
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('content-type', _cachedMimeType ?? 'video/mp4');
      request.response.headers.set('content-length', chunk.length.toString());
      request.response.headers.set('accept-ranges', 'bytes');
      request.response.add(chunk);
      await request.response.close();
      return;
    }
    
    // Send proper 206 Partial Content
    request.response.statusCode = 206;
    request.response.headers.set('content-type', _cachedMimeType ?? 'video/mp4');
    request.response.headers.set('content-length', chunk.length.toString());
    request.response.headers.set('content-range', 'bytes $start-$actualEnd/$_cachedFileSize');
    request.response.headers.set('accept-ranges', 'bytes');
    request.response.headers.set('access-control-allow-origin', '*');
    
    debugPrint('📤 206 Partial Content: bytes $start-$actualEnd/$_cachedFileSize (${chunk.length} bytes)');
    
    request.response.add(chunk);
    await request.response.close();
  }
  
  Future<void> _handleFullRequest(
    HttpRequest request,
    ChunkedRelayFetcher fetcher,
  ) async {
    debugPrint('📍 Full file request');
    
    // For full requests, return first chunk and let player request more
    final result = await fetcher.fetchChunkWithHeaders(0, ChunkedRelayFetcher.chunkSize - 1);
    
    if (result == null || result['data'] == null) {
      debugPrint('❌ Failed to fetch first chunk');
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    final chunk = result['data'] as Uint8List;
    
    // Send 206 even for "full" request to indicate partial content support
    request.response.statusCode = 206;
    request.response.headers.set('content-type', _cachedMimeType ?? 'video/mp4');
    request.response.headers.set('content-length', chunk.length.toString());
    request.response.headers.set('content-range', 'bytes 0-${chunk.length - 1}/$_cachedFileSize');
    request.response.headers.set('accept-ranges', 'bytes');
    request.response.headers.set('access-control-allow-origin', '*');
    
    debugPrint('📤 206 Partial Content: bytes 0-${chunk.length - 1}/$_cachedFileSize');
    
    request.response.add(chunk);
    await request.response.close();
  }
  
  String? getProxyUrl(String filePath) {
    if (_port == null) return null;
    return 'http://localhost:$_port/stream?path=${Uri.encodeComponent(filePath)}';
  }
  
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _port = null;
    _cachedFileSize = null;
    _cachedFilePath = null;
    _cachedMimeType = null;
    debugPrint('Streaming proxy server stopped');
  }
}
