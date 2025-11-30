import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_item.dart';
import '../storage/tag_database.dart';
import '../utils/hash_utils.dart';

class LocalFileProvider extends ChangeNotifier {
  List<FileItem> _files = [];
  List<FileItem> get files => _files;

  String _currentPath = '';
  String get currentPath => _currentPath;

  String _startDirectory = '';
  String get startDirectory => _startDirectory;

  static const String _startDirKey = 'start_directory';
  
  final TagDatabase _tagDb = TagDatabase();

  Future<void> initialize() async {
    // Load saved start directory or use default
    final prefs = await SharedPreferences.getInstance();
    _startDirectory = prefs.getString(_startDirKey) ?? await _getDefaultDirectory();
    await fetchFiles(_startDirectory);
  }

  Future<String> _getDefaultDirectory() async {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    } else if (Platform.isMacOS) {
      return Platform.environment['HOME'] ?? '/';
    } else {
      return '/';
    }
  }

  Future<void> setStartDirectory(String path) async {
    _startDirectory = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_startDirKey, path);
    await fetchFiles(path);
    notifyListeners();
  }

  Future<void> fetchFiles(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        debugPrint('Directory does not exist: $path');
        return;
      }

      _currentPath = path;
      final entities = await dir.list().toList();
      _files = [];

      for (var entity in entities) {
        try {
          final stat = await entity.stat();
          var fileItem = FileItem(
            path: entity.path,
            name: entity.path.split(Platform.pathSeparator).last,
            type: entity is Directory ? FileType.directory : FileType.file,
            size: stat.size,
          );
          
          // For files, compute hash and load tags
          if (entity is File) {
            final hash = await _tagDb.getHashForPath(entity.path);
            if (hash != null) {
              final tags = await _tagDb.getTags(hash);
              fileItem = fileItem.copyWith(tags: tags, sha256: hash);
            }
          }
          
          _files.add(fileItem);
        } catch (e) {
          debugPrint('Error accessing ${entity.path}: $e');
        }
      }

      // Sort: directories first, then files
      _files.sort((a, b) {
        if (a.type == b.type) {
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
        return a.type == FileType.directory ? -1 : 1;
      });

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching files: $e');
    }
  }


  Future<bool> moveItem(String oldPath, String newPath) async {
    try {
      final oldEntity = FileSystemEntity.typeSync(oldPath) == FileSystemEntityType.directory
          ? Directory(oldPath)
          : File(oldPath);
      
      debugPrint('Moving "$oldPath" to "$newPath"');
      
      // Check if destination already exists
      if (await FileSystemEntity.type(newPath) != FileSystemEntityType.notFound) {
        debugPrint('Destination already exists: $newPath');
        return false;
      }
      
      // Perform the move
      if (oldEntity is Directory) {
        await oldEntity.rename(newPath);
      } else if (oldEntity is File) {
        await oldEntity.rename(newPath);
      }
      
      // Refresh the current directory
      await fetchFiles(_currentPath);
      return true;
    } catch (e) {
      debugPrint('Error moving item: $e');
      return false;
    }
  }

  String? getParentPath() {
    if (_currentPath.isEmpty) return null;
    final dir = Directory(_currentPath);
    final parent = dir.parent;
    if (parent.path == _currentPath) return null; // At root
    return parent.path;
  }

  Future<bool> createFolder(String folderName) async {
    try {
      final newPath = '$_currentPath${Platform.pathSeparator}$folderName';
      final dir = Directory(newPath);
      
      if (await dir.exists()) {
        debugPrint('Folder already exists: $newPath');
        return false;
      }
      
      await dir.create();
      debugPrint('Created folder: $newPath');
      await fetchFiles(_currentPath); // Refresh
      return true;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return false;
    }
  }

  Future<bool> createTextFile(String fileName) async {
    try {
      final newPath = '$_currentPath${Platform.pathSeparator}$fileName';
      final file = File(newPath);
      
      if (await file.exists()) {
        debugPrint('File already exists: $newPath');
        return false;
      }
      
      await file.create();
      debugPrint('Created text file: $newPath');
      await fetchFiles(_currentPath); // Refresh
      return true;
    } catch (e) {
      debugPrint('Error creating text file: $e');
      return false;
    }
  }
  
  // Tag management methods
  Future<String?> computeAndStoreHash(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      
      final hash = await HashUtils.computeFileHash(filePath);
      final stat = await file.stat();
      
      await _tagDb.updateFileHash(
        filePath,
        hash,
        stat.modified.millisecondsSinceEpoch,
        stat.size,
      );
      
      return hash;
    } catch (e) {
      debugPrint('Error computing hash for $filePath: $e');
      return null;
    }
  }
  
  Future<void> addTagToFile(String path, String tag) async {
    String? hash = await _tagDb.getHashForPath(path);
    
    if (hash == null) {
      // Compute and store hash first
      hash = await computeAndStoreHash(path);
      if (hash == null) return;
    }
    
    await _tagDb.addTag(hash, tag);
    await fetchFiles(_currentPath); // Refresh
  }
  
  Future<void> removeTagFromFile(String path, String tag) async {
    final hash = await _tagDb.getHashForPath(path);
    if (hash != null) {
      await _tagDb.removeTag(hash, tag);
      await fetchFiles(_currentPath); // Refresh
    }
  }
  
  Future<List<String>> getAllTags() async {
    return await _tagDb.getAllTags();
  }
  
  Future<void> updateFileTags(String path, List<String> newTags) async {
    String? hash = await _tagDb.getHashForPath(path);
    
    if (hash == null) {
      // Compute and store hash first
      hash = await computeAndStoreHash(path);
      if (hash == null) return;
    }
    
    // Get current tags
    final currentTags = await _tagDb.getTags(hash);
    
    // Remove tags that are no longer present
    for (final tag in currentTags) {
      if (!newTags.contains(tag)) {
        await _tagDb.removeTag(hash, tag);
      }
    }
    
    // Add new tags
    for (final tag in newTags) {
      if (!currentTags.contains(tag)) {
        await _tagDb.addTag(hash, tag);
      }
    }
    
    await fetchFiles(_currentPath); // Refresh
  }
}
