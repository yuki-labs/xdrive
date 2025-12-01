import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

/// Manages file and folder operations (create, delete, rename, move, upload)
class FileOperationsManager {
  final nsd.Service? Function() _getConnectedService;
  final Future<void> Function(String path) _refreshFiles;
  
  FileOperationsManager({
    required nsd.Service? Function() getConnectedService,
    required Future<void> Function(String path) refreshFiles,
  })  : _getConnectedService = getConnectedService,
        _refreshFiles = refreshFiles;

  Future<bool> createFolder(String currentPath, String folderName) async {
    final service = _getConnectedService();
    if (service == null) return false;

    try {
      final url = 'http://${service.host}:${service.port}/create';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'path': currentPath,
          'name': folderName,
          'isDirectory': true,
        }),
      );

      if (response.statusCode == 200) {
        await _refreshFiles(currentPath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return false;
    }
  }

  Future<bool> createTextFile(String currentPath, String fileName) async {
    final service = _getConnectedService();
    if (service == null) return false;

    try {
      final url = 'http://${service.host}:${service.port}/create';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'path': currentPath,
          'name': fileName,
          'isDirectory': false,
        }),
      );

      if (response.statusCode == 200) {
        await _refreshFiles(currentPath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error creating text file: $e');
      return false;
    }
  }

  Future<bool> deleteItem(String path, String currentPath) async {
    final service = _getConnectedService();
    if (service == null) return false;

    try {
      final url = 'http://${service.host}:${service.port}/delete';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      );

      if (response.statusCode == 200) {
        await _refreshFiles(currentPath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting item: $e');
      return false;
    }
  }

  Future<bool> renameItem(String oldPath, String newName, String currentPath) async {
    final service = _getConnectedService();
    if (service == null) return false;

    try {
      // Detect separator from the path itself (works cross-platform)
      String separator = '/';
      if (oldPath.contains('\\')) {
        separator = '\\';
      }
      
      // Extract directory from old path
      final separatorIndex = oldPath.lastIndexOf(separator);
      final String directory;
      
      if (separatorIndex == -1) {
        directory = '';
      } else if (separatorIndex == 0) {
        directory = separator;
      } else {
        directory = oldPath.substring(0, separatorIndex);
      }
      
      // Construct new path with same separator
      final newPath = directory.isEmpty
          ? newName
          : directory == separator
              ? '$separator$newName'
              : '$directory$separator$newName';

      final url = 'http://${service.host}:${service.port}/move';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPath': oldPath,
          'newPath': newPath,
        }),
      );

      if (response.statusCode == 200) {
        await _refreshFiles(currentPath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error renaming item: $e');
      return false;
    }
  }

  Future<bool> moveItem(String oldPath, String newPath, String currentPath) async {
    final service = _getConnectedService();
    if (service == null) return false;

    try {
      final url = 'http://${service.host}:${service.port}/move';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPath': oldPath,
          'newPath': newPath,
        }),
      );

      if (response.statusCode == 200) {
        await _refreshFiles(currentPath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error moving item: $e');
      return false;
    }
  }

  Future<bool> uploadFile(String filePath, String remotePath, String fileName) async {
    final service = _getConnectedService();
    if (service == null) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final url = 'http://${service.host}:${service.port}/upload?path=${Uri.encodeComponent(remotePath)}&filename=${Uri.encodeComponent(fileName)}';
      
      final request = http.StreamedRequest('POST', Uri.parse(url));
      final fileLength = await file.length();
      request.headers['content-length'] = fileLength.toString();
      
      final stream = file.openRead();
      stream.listen(
        (chunk) => request.sink.add(chunk),
        onDone: () => request.sink.close(),
        onError: (e) {
          debugPrint('Error reading file: $e');
          request.sink.close();
        },
      );

      final response = await request.send();
      if (response.statusCode == 200) {
        await _refreshFiles(remotePath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return false;
    }
  }
}
