import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;
import '../storage/tag_database.dart';
import '../crypto/encryption_service.dart';

/// Manages tag operations, hash computation, and tag synchronization
class TagManager {
  final TagDatabase _tagDb = TagDatabase();
  final nsd.Service? Function() _getConnectedService;
  final Future<void> Function(String path) _refreshFiles;
  final bool Function() _isUsingRelay;
  final Future<String?> Function(String method, String path) _httpViaRelay;
  final Uint8List? Function() _getEncryptionKey;
  
  TagManager({
    required nsd.Service? Function() getConnectedService,
    required Future<void> Function(String path) refreshFiles,
    required bool Function() isUsingRelay,
    required Future<String?> Function(String method, String path) httpViaRelay,
    required Uint8List? Function() getEncryptionKey,
  })  : _getConnectedService = getConnectedService,
        _refreshFiles = refreshFiles,
        _isUsingRelay = isUsingRelay,
        _httpViaRelay = httpViaRelay,
        _getEncryptionKey = getEncryptionKey;

  Future<void> addTagToFile(String path, String tag, String currentPath) async {
    String? hash = await _tagDb.getHashForPath(path);
    
    if (hash == null) {
      debugPrint('Cannot add tag: hash not found for $path');
      return;
    }
    
    await _tagDb.addTag(hash, tag);
    await _refreshFiles(currentPath);
  }
  
  Future<void> removeTagFromFile(String path, String tag, String currentPath) async {
    final hash = await _tagDb.getHashForPath(path);
    if (hash != null) {
      await _tagDb.removeTag(hash, tag);
      await _refreshFiles(currentPath);
    }
  }
  
  Future<List<String>> getAllTags() async {
    return await _tagDb.getAllTags();
  }
  
  Future<List<String>> getTagsForPath(String path) async {
    return await _tagDb.getTags(path);
  }
  
  Future<String?> getHashForPath(String path) async {
    return await _tagDb.getHashForPath(path);
  }
  
  /// Ensures a file has a hash computed, without modifying tags
  Future<Map<String, dynamic>> ensureFileHasHash(String path) async {
    String? hash = await _tagDb.getHashForPath(path);
    
    if (hash != null) {
      return {'success': true, 'hash': hash};
    }
    
    try {
      final service = _getConnectedService();
      if (service == null) {
        return {'success': false, 'error': 'Not connected to any server'};
      }

      final uri = Uri.http('${service.host}:${service.port}', '/file-hash', {'path': path});
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        hash = data['hash'] as String;
        final size = data['size'] as int;
        final modified = data['modified'] as int;
        
        await _tagDb.updateFileHash(path, hash, modified, size);
        
        debugPrint('Computed and stored hash: $path → $hash');
        return {'success': true, 'hash': hash};
      } else {
        return {'success': false, 'error': 'Failed to get file hash from server (HTTP ${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Error requesting hash from server: $e'};
    }
  }
  
  Future<Map<String, dynamic>> updateFileTags(
    String path, 
    List<String> newTags, 
    String currentPath,
    {bool refresh = true}
  ) async {
    debugPrint('===== updateFileTags called =====');
    debugPrint('Path: $path');
    debugPrint('New tags: $newTags');
    
    String? hash = await _tagDb.getHashForPath(path);
    debugPrint('Hash from database: $hash');
    
    if (hash == null) {
      debugPrint('No hash found, triggering background hash computation');
      _computeHashInBackground(path);
    }
    
    try {
      final pathTags = await _tagDb.getTags(path);
      final hashTags = hash != null ? await _tagDb.getTags(hash) : <String>[];
      
      final currentTags = {...pathTags, ...hashTags}.toList();
      debugPrint('Merged current tags: $currentTags');
      
      // Update tags under PATH
      for (final tag in currentTags) {
        if (!newTags.contains(tag)) {
          await _tagDb.removeTag(path, tag);
        }
      }
      for (final tag in newTags) {
        if (!pathTags.contains(tag)) {
          await _tagDb.addTag(path, tag);
        }
      }
      
      // Update tags under HASH
      if (hash != null && hash != path) {
        for (final tag in currentTags) {
          if (!newTags.contains(tag)) {
            await _tagDb.removeTag(hash, tag);
          }
        }
        for (final tag in newTags) {
          if (!hashTags.contains(tag)) {
            await _tagDb.addTag(hash, tag);
          }
        }
      }
      
      // Push to server
      final syncKey = hash ?? path;
      final syncResult = await syncTagsToServer(syncKey, newTags);
      if (!syncResult['success']) {
        return {'success': false, 'error': 'Tags saved locally but sync failed: ${syncResult['error']}'};
      }
      
      if (refresh) {
        await _refreshFiles(currentPath);
      }
      
      return {'success': true};
    } catch (e) {
      debugPrint('Error in updateFileTags: $e');
      return {'success': false, 'error': 'Error updating tags in database: $e'};
    }
  }
  
  void _computeHashInBackground(String path) {
    debugPrint('Starting background hash computation for: $path');
    ensureFileHasHash(path).then((result) {
      if (result['success']) {
        final realHash = result['hash'] as String;
        debugPrint('Background hash computed: $path → $realHash');
        syncTagsToHashIndex(path, realHash);
      }
    }).catchError((e) {
      debugPrint('Error in background hash computation: $e');
    });
  }
  
  Future<void> syncTagsToHashIndex(String path, String hash) async {
    if (path == hash) return;
    
    debugPrint('Syncing tags from path to hash index: $path → $hash');
    
    try {
      final pathTags = await _tagDb.getTags(path);
      final hashTags = await _tagDb.getTags(hash);
      
      if (pathTags.isNotEmpty) {
        for (final tag in pathTags) {
          if (!hashTags.contains(tag)) {
            await _tagDb.addTag(hash, tag);
            debugPrint('Synced tag to hash index: $tag');
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing tags to hash index: $e');
    }
  }
  
  Future<Map<String, dynamic>> syncTagsToServer(String hash, List<String> tags) async {
    final service = _getConnectedService();
    if (service == null) {
      return {'success': false, 'error': 'Not connected to server'};
    }
    
    try {
      final host = service.host;
      final port = service.port;
      
      // Get current tags from server
      final getUri = Uri.http('$host:$port', '/tags/$hash');
      final getResponse = await http.get(getUri);
      
      List<String> serverTags = [];
      if (getResponse.statusCode == 200) {
        final data = jsonDecode(getResponse.body);
        serverTags = List<String>.from(data['tags'] ?? []);
      }
      
      final tagsToAdd = tags.where((tag) => !serverTags.contains(tag)).toList();
      final tagsToRemove = serverTags.where((tag) => !tags.contains(tag)).toList();
      
      // Add new tags
      for (final tag in tagsToAdd) {
        final addUri = Uri.http('$host:$port', '/tags/add');
        final response = await http.post(
          addUri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'hash': hash, 'tag': tag}),
        );
        if (response.statusCode != 200) {
          return {'success': false, 'error': 'Failed to add tag "$tag" to server'};
        }
      }
      
      // Remove old tags
      for (final tag in tagsToRemove) {
        final removeUri = Uri.http('$host:$port', '/tags/remove');
        final response = await http.post(
          removeUri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'hash': hash, 'tag': tag}),
        );
        if (response.statusCode != 200) {
          return {'success': false, 'error': 'Failed to remove tag "$tag" from server'};
        }
      }
      
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': 'Network error while syncing: $e'};
    }
  }
  
  Future<void> syncTagsFromServer() async {
    final service = _getConnectedService();
    if (service == null) return;
    
    try {
      String? responseBody;
      
      if (_isUsingRelay()) {
        debugPrint('Syncing tags via relay...');
        responseBody = await _httpViaRelay('GET', '/tags/all-hashes');
      } else {
        final uri = Uri.http('${service.host}:${service.port}', '/tags/all-hashes');
        final response = await http.get(uri);
        
        if (response.statusCode == 200) {
          responseBody = response.body;
          
          final encryptionKey = _getEncryptionKey();
          if (response.headers['x-encrypted'] == 'true' && encryptionKey != null) {
            responseBody = EncryptionService.decryptString(responseBody, encryptionKey);
          }
        }
      }
      
      if (responseBody == null) return;
      
      final data = jsonDecode(responseBody);
      final hashTagsMap = Map<String, List<dynamic>>.from(data['hashTags'] ?? {});
      
      for (final entry in hashTagsMap.entries) {
        final hash = entry.key;
        final serverTags = List<String>.from(entry.value);
        final localTags = await _tagDb.getTags(hash);
        
        for (final tag in localTags) {
          if (!serverTags.contains(tag)) {
            await _tagDb.removeTag(hash, tag);
          }
        }
        
        for (final tag in serverTags) {
          if (!localTags.contains(tag)) {
            await _tagDb.addTag(hash, tag);
          }
        }
      }
      
      debugPrint('Synced tags from server');
    } catch (e) {
      debugPrint('Error syncing tags from server: $e');
    }
  }
}
