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
  
  // Cache file metadata
  int? _cachedFileSize;
  String? _cachedFilePath;
  
  StreamingProxyServer({required this.relayConnection});
  
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
      
      if (path == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing path parameter');
        await request.response.close();
        return;
      }
      
      debugPrint('Streaming request for: $path');
      
      // Create chunked fetcher
      final fetcher = ChunkedRelayFetcher(
        relayConnection: relayConnection,
        filePath: path,
      );
      
      // Handle range requests
      final rangeHeader = request.headers.value('range');
      
      if (rangeHeader != null) {
        await _handleRangeRequest(request, fetcher, path, rangeHeader);
      } else {
        await _handleFullRequest(request, fetcher, path);
      }
    } catch (e) {
      debugPrint('Error handling streaming request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
  
  /// Get file size using /file-info endpoint
  Future<int?> _getFileSize(ChunkedRelayFetcher fetcher, String path) async {
    // Return cached if same file
    if (_cachedFilePath == path && _cachedFileSize != null) {
      return _cachedFileSize;
    }
    
    try {
      final fileInfo = await fetcher.getFileInfo();
      
      if (fileInfo != null && fileInfo['size'] != null) {
        _cachedFileSize = fileInfo['size'] as int;
        _cachedFilePath = path;
        debugPrint('File size from /file-info: $_cachedFileSize bytes');
        return _cachedFileSize;
      }
    } catch (e) {
      debugPrint('Error getting file size: $e');
    }
    
    return null;
  }
  
  Future<void> _handleRangeRequest(
    HttpRequest request,
    ChunkedRelayFetcher fetcher,
    String path,
    String rangeHeader,
  ) async {
    // Parse range: "bytes=0-1000"
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    
    if (match == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    
    final start = int.parse(match.group(1)!);
    final endStr = match.group(2);
    
    // Fetch the requested chunk
    final end = endStr != null && endStr.isNotEmpty
        ? int.parse(endStr)
        : start + ChunkedRelayFetcher.chunkSize - 1;
    
    final result = await fetcher.fetchChunkWithHeaders(start, end);
    
    if (result == null || result['data'] == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    final chunk = result['data'] as Uint8List;
    final actualEnd = start + chunk.length - 1;
    
    // Get file size for proper Content-Range
    final fileSize = await _getFileSize(fetcher, path);
    
    // Send partial content
    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set('content-type', _getMimeType(path));
    request.response.headers.set('content-length', chunk.length.toString());
    
    // Use actual file size if available
    if (fileSize != null) {
      request.response.headers.set('content-range', 'bytes $start-$actualEnd/$fileSize');
      debugPrint('Content-Range: bytes $start-$actualEnd/$fileSize');
    } else {
      request.response.headers.set('content-range', 'bytes $start-$actualEnd/*');
    }
    
    request.response.headers.set('accept-ranges', 'bytes');
    request.response.add(chunk);
    await request.response.close();
  }
  
  Future<void> _handleFullRequest(
    HttpRequest request,
    ChunkedRelayFetcher fetcher,
    String path,
  ) async {
    // Stream file progressively
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('content-type', _getMimeType(path));
    request.response.headers.set('accept-ranges', 'bytes');
    
    await fetcher.fetchProgressive(
      onChunk: (chunk, offset) {
        request.response.add(chunk);
      },
      onComplete: () async {
        await request.response.close();
      },
      onError: (error) async {
        debugPrint('Streaming error: $error');
        await request.response.close();
      },
    );
  }
  
  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': return 'video/mp4';
      case 'mkv': return 'video/x-matroska';
      case 'webm': return 'video/webm';
      case 'mov': return 'video/quicktime';
      case 'avi': return 'video/x-msvideo';
      case 'mp3': return 'audio/mpeg';
      case 'flac': return 'audio/flac';
      case 'ogg': return 'audio/ogg';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      default: return 'application/octet-stream';
    }
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
    debugPrint('Streaming proxy server stopped');
  }
}
