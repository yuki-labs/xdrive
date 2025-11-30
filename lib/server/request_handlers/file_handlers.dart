import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import '../../models/file_item.dart';
import '../utils/encryption_helper.dart';
import '../utils/thumbnail_generator.dart';
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

  /// Handle GET /stream request
  Future<Response> handleStreamFile(Request request) async {
    final queryParams = request.url.queryParameters;
    final path = queryParams['path'];

    if (path == null) {
      return Response.badRequest(body: 'Missing path parameter');
    }

    final file = File(path);
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': mimeType,
        'content-length': '${await file.length()}',
      },
    );
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
