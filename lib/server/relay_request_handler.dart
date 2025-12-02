import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'request_handlers/file_handlers.dart';
import 'request_handlers/tag_handlers.dart';

/// Handles parsing and routing of relay requests
class RelayRequestHandler {
  final FileHandlers fileHandlers;
  final TagHandlers tagHandlers;
  final void Function(String requestId, String data) sendResponse;
  
  RelayRequestHandler({
    required this.fileHandlers,
    required this.tagHandlers,
    required this.sendResponse,
  });
  
  /// Handle incoming relay request
  Future<void> handleRequest(Map<String, dynamic> message) async {
    final requestId = message['requestId'] as String;
    final data = message['data'] as String;
    
    try {
      final requestBytes = base64.decode(data);
      final requestText = utf8.decode(requestBytes);
      
      debugPrint('Received relay request: $requestId');
      debugPrint('Request: ${requestText.substring(0, min(100, requestText.length))}...');
      
      // Parse HTTP request
      final lines = requestText.split('\r\n');
      if (lines.isEmpty) {
        debugPrint('Invalid HTTP request');
        return;
      }
      
      // Extract request line
      final requestLine = lines[0];
      final parts = requestLine.split(' ');
      if (parts.length < 2) {
        debugPrint('Invalid HTTP request line');
        return;
      }
      
      final method = parts[0];
      final pathWithQuery = parts[1];
      
      // Parse headers
      final Map<String, String> headers = {};
      for (int i = 1; i < lines.length; i++) {
        if (lines[i].isEmpty) break;
        final colonIndex = lines[i].indexOf(':');
        if (colonIndex > 0) {
          final key = lines[i].substring(0, colonIndex).trim().toLowerCase();
          final value = lines[i].substring(colonIndex + 1).trim();
          headers[key] = value;
        }
      }
      
      // Parse URI
      Uri uri;
      try {
        uri = Uri.parse('http://localhost$pathWithQuery');
      } catch (e) {
        debugPrint('Failed to parse URI: $pathWithQuery');
        return;
      }
      
      // Route to handler
      final response = await _routeRequest(method, uri, headers);
      
      // Encode and send response
      final contentType = response.headers['content-type'] ?? '';
      final isBinary = contentType.startsWith('image/') || contentType.startsWith('video/');
      final responseData = isBinary
          ? base64.encode(await response.read().toList().then((chunks) =>
              chunks.expand((chunk) => chunk).toList()))
          : base64.encode(utf8.encode(await response.readAsString()));
      
      sendResponse(requestId, responseData);
      debugPrint('Sent response for request $requestId');
      
    } catch (e) {
      debugPrint('Error handling relay request: $e');
    }  
  }
  
  Future<Response> _routeRequest(String method, Uri uri, Map<String, String> headers) async {
    if (uri.path == '/files') {
      return await fileHandlers.handleGetFiles(Request(method, uri));
    } else if (uri.path == '/file-info') {
      return await fileHandlers.handleGetFileInfo(Request(method, uri));
    } else if (uri.path == '/tags/all-hashes') {
      return await tagHandlers.handleGetAllTaggedHashes(Request(method, uri));
    } else if (uri.path == '/thumbnail') {
      return await fileHandlers.handleGetThumbnail(Request(method, uri));
    } else if (uri.path == '/stream') {
      // Pass headers for range requests!
      return await fileHandlers.handleStreamFile(Request(method, uri, headers: headers));
    } else {
      return Response.notFound('Not found');
    }
  }
}
