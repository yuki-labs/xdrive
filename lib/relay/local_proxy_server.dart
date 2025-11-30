import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Local HTTP server that proxies file requests through relay
class LocalProxyServer {
  HttpServer? _server;
  int? _port;
  final Future<Uint8List?> Function(String path) fetchViaRelay;
  
  // Cache for currently streaming file
  Uint8List? _cachedFileData;
  String? _cachedFilePath;
  
  LocalProxyServer({required this.fetchViaRelay});
  
  Future<String?> start() async {
    try {
      // Start server on random available port
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      
      debugPrint('Local proxy server started on localhost:$_port');
      
      _server!.listen((HttpRequest request) async {
        await _handleRequest(request);
      });
      
      return 'http://localhost:$_port';
    } catch (e) {
      debugPrint('Failed to start proxy server: $e');
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
      
      // Fetch file data (use cache if same file)
      Uint8List? fileData;
      if (_cachedFilePath == path && _cachedFileData != null) {
        fileData = _cachedFileData;
        debugPrint('Using cached file data for $path');
      } else {
        debugPrint('Fetching file via relay: $path');
        fileData = await fetchViaRelay(path);
        if (fileData != null) {
          _cachedFileData = fileData;
          _cachedFilePath = path;
        }
      }
      
      if (fileData == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      
      // Handle range requests for video seeking
      final rangeHeader = request.headers.value('range');
      if (rangeHeader != null) {
        _handleRangeRequest(request, fileData, rangeHeader);
      } else {
        _handleFullRequest(request, fileData, path);
      }
    } catch (e) {
      debugPrint('Error handling proxy request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
  
  void _handleRangeRequest(HttpRequest request, Uint8List data, String rangeHeader) async {
    // Parse range header: "bytes=0-1000"
    final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
    if (match == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    
    final start = int.parse(match.group(1)!);
    final end = match.group(2)!.isEmpty ? data.length - 1 : int.parse(match.group(2)!);
    
    final rangeData = data.sublist(start, end + 1);
    
    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set('content-type', _getMimeType(request.uri.queryParameters['path'] ?? ''));
    request.response.headers.set('content-length', rangeData.length);
    request.response.headers.set('content-range', 'bytes $start-$end/${data.length}');
    request.response.headers.set('accept-ranges', 'bytes');
    request.response.add(rangeData);
    await request.response.close();
  }
  
  void _handleFullRequest(HttpRequest request, Uint8List data, String path) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('content-type', _getMimeType(path));
    request.response.headers.set('content-length', data.length);
    request.response.headers.set('accept-ranges', 'bytes');
    request.response.add(data);
    await request.response.close();
  }
  
  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': return 'video/mp4';
      case 'mkv': return 'video/x-matroska';
      case 'webm': return 'video/webm';
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
  
  void clearCache() {
    _cachedFileData = null;
    _cachedFilePath = null;
  }
  
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _port = null;
    clearCache();
    debugPrint('Local proxy server stopped');
  }
}
