import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;

/// Handles file CRUD operations (create, rename, delete, move)
class FileOperations {
  final nsd.Service? connectedService;
  
  FileOperations({required this.connectedService});
  
  Future<bool> createFolder(String currentPath, String folderName) async {
    if (connectedService == null) return false;

    try {
      final url = 'http://${connectedService!.host}:${connectedService!.port}/create';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'path': currentPath,
          'name': folderName,
          'isDirectory': true,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return false;
    }
  }

  Future<bool> createTextFile(String currentPath, String fileName) async {
    if (connectedService == null) return false;

    try {
      final url = 'http://${connectedService!.host}:${connectedService!.port}/create';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'path': currentPath,
          'name': fileName,
          'isDirectory': false,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error creating text file: $e');
      return false;
    }
  }

  Future<bool> deleteItem(String path) async {
    if (connectedService == null) return false;

    try {
      final url = 'http://${connectedService!.host}:${connectedService!.port}/delete';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting item: $e');
      return false;
    }
  }

  Future<bool> renameItem(String oldPath, String newName) async {
    if (connectedService == null) return false;

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

      final url = 'http://${connectedService!.host}:${connectedService!.port}/move';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPath': oldPath,
          'newPath': newPath,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error renaming item: $e');
      return false;
    }
  }

  Future<bool> moveItem(String oldPath, String newPath) async {
    if (connectedService == null) return false;

    try {
      final url = 'http://${connectedService!.host}:${connectedService!.port}/move';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPath': oldPath,
          'newPath': newPath,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error moving item: $e');
      return false;
    }
  }

  Future<bool> uploadFile(String filePath, String remotePath, String fileName) async {
    if (connectedService == null) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('File does not exist: $filePath');
        return false;
      }

      final url = 'http://${connectedService!.host}:${connectedService!.port}/upload';
      final request = http.MultipartRequest('POST', Uri.parse(url));
      
      request.fields['path'] = remotePath;
      request.fields['name'] = fileName;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return false;
    }
  }
}
