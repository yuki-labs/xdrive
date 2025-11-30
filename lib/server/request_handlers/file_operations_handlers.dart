import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../../utils/hash_utils.dart';

/// Handles file operations (create, delete, move, upload, hash)
class FileOperationsHandlers {
  final String? rootDirectory;

  FileOperationsHandlers({required this.rootDirectory});

  /// Handle GET /file-hash
  Future<Response> handleGetFileHash(Request request) async {
    final queryParams = request.url.queryParameters;
    final path = queryParams['path'];

    if (path == null) {
      return Response.badRequest(body: 'Missing path parameter');
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      final stat = await file.stat();
      final fileSizeMB = (stat.size / (1024 * 1024)).toStringAsFixed(2);
      print('Computing hash for file: $path ($fileSizeMB MB)');
      
      final startTime = DateTime.now();
      final hash = await HashUtils.computeFileHash(path);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      
      print('Hash computed in ${duration}ms: $hash');

      return Response.ok(
        jsonEncode({
          'hash': hash,
          'size': stat.size,
          'modified': stat.modified.millisecondsSinceEpoch,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('ERROR computing hash: $e');
      return Response.internalServerError(body: 'Error computing hash: $e');
    }
  }

  /// Handle POST /create
  Future<Response> handleCreateItem(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final path = data['path'] as String?;
      final name = data['name'] as String?;
      final isDirectory = data['isDirectory'] as bool? ?? true;

      if (path == null || name == null) {
        return Response.badRequest(body: 'Missing path or name');
      }

      String basePath = path;
      if (basePath == '/' || basePath == '\\') {
        basePath = rootDirectory ?? Directory.current.path;
      }

      final fullPath = '$basePath${Platform.pathSeparator}$name';
      print('Creating item at: $fullPath');

      if (isDirectory) {
        final dir = Directory(fullPath);
        await dir.create();
        print('Created directory: $fullPath');
      } else {
        final file = File(fullPath);
        await file.create();
        print('Created file: $fullPath');
      }

      return Response.ok(jsonEncode({'success': true, 'path': fullPath}));
    } catch (e) {
      print('Error creating item: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Handle POST /delete
  Future<Response> handleDeleteItem(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final path = data['path'] as String?;

      if (path == null) {
        return Response.badRequest(body: 'Missing path');
      }

      final file = File(path);
      final dir = Directory(path);

      if (await file.exists()) {
        await file.delete();
        print('Deleted file: $path');
      } else if (await dir.exists()) {
        await dir.delete(recursive: true);
        print('Deleted directory: $path');
      } else {
        return Response.notFound('Item not found');
      }

      return Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      print('Error deleting item: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Handle POST /move
  Future<Response> handleMoveItem(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final oldPath = data['oldPath'] as String?;
      final newPath = data['newPath'] as String?;

      if (oldPath == null || newPath == null) {
        return Response.badRequest(body: 'Missing oldPath or newPath');
      }

      final file = File(oldPath);
      final dir = Directory(oldPath);

      if (await file.exists()) {
        await file.rename(newPath);
        print('Moved file: $oldPath -> $newPath');
      } else if (await dir.exists()) {
        await dir.rename(newPath);
        print('Moved directory: $oldPath -> $newPath');
      } else {
        return Response.notFound('Item not found');
      }

      return Response.ok(jsonEncode({'success': true}));
    } catch (e) {
      print('Error moving item: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Handle POST /upload
  Future<Response> handleUploadFile(Request request) async {
    try {
      final contentLength = request.headers['content-length'];
      if (contentLength == null) {
        return Response.badRequest(body: 'Missing content-length header');
      }

      final queryParams = request.url.queryParameters;
      final path = queryParams['path'];
      final filename = queryParams['filename'];

      if (path == null || filename == null) {
        return Response.badRequest(body: 'Missing path or filename parameter');
      }

      final fullPath = '$path${Platform.pathSeparator}$filename';
      final file = File(fullPath);

      await file.parent.create(recursive: true);

      final sink = file.openWrite();
      await request.read().forEach((chunk) {
        sink.add(chunk);
      });
      await sink.close();

      print('Uploaded file: $fullPath');
      return Response.ok(jsonEncode({'success': true, 'path': fullPath}));
    } catch (e) {
      print('Error uploading file: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }
}
