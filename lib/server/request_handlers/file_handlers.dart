import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import '../../models/file_item.dart';
import '../utils/encryption_helper.dart';
import '../utils/thumbnail_generator.dart';
import '../utils/codec_detector.dart';
import 'package:mime/mime.dart';

/// Handles file-related HTTP requests
class FileHandlers {
  final String? rootDirectory;
  final Uint8List? encryptionKey;
  final ThumbnailGenerator thumbnailGenerator;

  FileHandlers({
    required this.rootDirectory,
    required this.encryptionKey,
    required this.thumbnailGenerator,
  });

  /// Handle GET /files request
  Future<Response> handleGetFiles(Request request) async {
    final queryParams = request.url.queryParameters;
    String path = queryParams['path'] ?? rootDirectory ?? Directory.current.path;

    if (path == '/' || path == '\\') {
      path = rootDirectory ?? Directory.current.path;
    }

    final dir = Directory(path);
    if (!await dir.exists()) {
      return Response.notFound('Directory not found');
    }

    try {
      final entities = await dir.list().toList();
      final fileItems = <FileItem>[];

      for (var entity in entities) {
        final stat = await entity.stat();
        fileItems.add(FileItem(
          path: entity.path,
          name: entity.path.split(Platform.pathSeparator).last,
          type: entity is Directory ? FileType.directory : FileType.file,
          size: stat.size,
        ));
      }

      final jsonBody = jsonEncode({
        'rootPath': rootDirectory ?? Directory.current.path,
        'files': fileItems.map((e) => e.toJson()).toList(),
      });
      
      return EncryptionHelper.encryptResponse(jsonBody, encryptionKey);
    } catch (e) {
      return Response.internalServerError(body: 'Error listing directory: $e');
    }
  }

  /// Handle GET /stream request with optional transcoding
  Future<Response> handleStreamFile(Request request) async {
    final queryParams = request.url.queryParameters;
    final path = queryParams['path'];
    final transcode = queryParams['transcode'] == 'true';

    if (path == null) {
      return Response.badRequest(body: 'Missing path parameter');
    }

    final file = File(path);
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    // Check if transcoding is requested
    if (transcode && await CodecDetector.isFFmpegAvailable()) {
      return _streamTranscodedFile(request, file);
    }

    final fileLength = await file.length();
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    
    // Check for range request
    final rangeHeader = request.headers['range'];
    
    if (rangeHeader != null) {
      // Parse range header: "bytes=0-1000" or "bytes=1000-"
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final endStr = match.group(2);
        final end = endStr != null && endStr.isNotEmpty 
            ? int.parse(endStr) 
            : fileLength - 1;
        
        if (start >= fileLength || end >= fileLength || start > end) {
          return Response(416, body: 'Requested range not satisfiable');
        }
        
        final length = end - start + 1;
        
        // Return partial content (stream the chunk)
        return Response(206,
          body: file.openRead(start, end + 1),
          headers: {
            'content-type': mimeType,
            'content-length': '$length',
            'content-range': 'bytes $start-$end/$fileLength',
            'accept-ranges': 'bytes',
          },
        );
      }
    }
    
    // No range request, return full file stream
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': mimeType,
        'content-length': '$fileLength',
        'accept-ranges': 'bytes',
      },
    );
  }

  /// Stream transcoded video (H.264/AAC in MP4)
  Future<Response> _streamTranscodedFile(Request request, File file) async {
    try {
      final args = CodecDetector.getTranscodeArgs(file.path);
      
      final process = await Process.start('ffmpeg', args);
      
      // Stream transcoded output
      return Response.ok(
        process.stdout,
        headers: {
          'content-type': 'video/mp4',
          'accept-ranges': 'none', // Transcoding doesn't support range requests
          'cache-control': 'no-cache',
        },
      );
    } catch (e) {
      print('Transcoding error: $e');
      return Response.internalServerError(body: 'Transcoding failed');
    }
  }

  /// Handle GET /file-info request - returns file metadata with codec info
  Future<Response> handleGetFileInfo(Request request) async {
    final queryParams = request.url.queryParameters;
    final path = queryParams['path'];

    if (path == null) {
      return Response.badRequest(body: 'Missing path parameter');
    }

    final file = File(path);
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    try {
      final size = await file.length();
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      
      // Check if file needs transcoding
      bool needsTranscoding = false;
      if (mimeType.startsWith('video/')) {
        needsTranscoding = await CodecDetector.needsTranscoding(path);
      }

      final jsonBody = jsonEncode({
        'size': size,
        'mimeType': mimeType,
        'needsTranscoding': needsTranscoding,
      });
      
      return EncryptionHelper.encryptResponse(jsonBody, encryptionKey);
    } catch (e) {
      return Response.internalServerError(body: 'Error getting file info: $e');
    }
  }

  /// Handle GET /thumbnail request
  Future<Response> handleGetThumbnail(Request request) async {
    final queryParams = request.url.queryParameters;
    final path = queryParams['path'];

    if (path == null) {
      return Response.badRequest(body: 'Missing path parameter');
    }

    return await thumbnailGenerator.generateThumbnail(path);
  }
}
