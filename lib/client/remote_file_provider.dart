import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_item.dart';
import '../storage/tag_database.dart';
import '../utils/hash_utils.dart';
import '../crypto/encryption_service.dart';
import '../relay/relay_connection.dart';

class RemoteFileProvider extends ChangeNotifier {
  List<nsd.Service> _discoveredServices = [];
  List<nsd.Service> get discoveredServices => _discoveredServices;

  nsd.Service? _connectedService;
  nsd.Service? get connectedService => _connectedService;

  List<FileItem> _files = [];
  List<FileItem> get files => _files;

  String? _serverRootPath;
  String? get serverRootPath => _serverRootPath;

  nsd.Discovery? _discovery;
  
  final TagDatabase _tagDb = TagDatabase();
  
  // Encryption
  Uint8List? _encryptionKey;
  
  // Track decryption failures
  bool _decryptionFailed = false;
  bool get decryptionFailed => _decryptionFailed;
  
  // Callback for when decryption fails
  Function()? onDecryptionFailed;
  
  // Relay connection
  RelayConnection? _relayConnection;
  bool _usingRelay = false;


  Future<void> startDiscovery() async {
    _discovery = await nsd.startDiscovery('_http._tcp');
    _discovery!.addServiceListener((service, status) {
      if (status == nsd.ServiceStatus.found) {
        debugPrint('Service discovered: name="${service.name}", host=${service.host}, port=${service.port}');
        
        // Check if this service is already in the list (by host:port)
        final existingIndex = _discoveredServices.indexWhere((s) =>
            s.host == service.host && s.port == service.port);
        
        if (existingIndex == -1) {
          // New service, add it
          _discoveredServices.add(service);
          notifyListeners();
        } else {
          // Service exists, check if new name is better
          final existing = _discoveredServices[existingIndex];
          final existingName = existing.name ?? '';
          final newName = service.name ?? '';
          
          // Prefer names that don't have (1), (2) etc. - these are duplicates
          final existingHasNumber = existingName.contains(RegExp(r'\(\d+\)'));
          final newHasNumber = newName.contains(RegExp(r'\(\d+\)'));
          
          if (!newHasNumber && existingHasNumber) {
            // Upgrade: New name is better (actual hostname), replace it
            debugPrint('Updating service name from "$existingName" to "$newName"');
            _discoveredServices[existingIndex] = service;
            notifyListeners();
          } else if (newHasNumber && !existingHasNumber) {
            // Protect: Don't downgrade from actual hostname to numbered variant
            debugPrint('Keeping actual hostname "$existingName", ignoring numbered variant "${service.name}"');
          } else {
            // Both numbered or both non-numbered, keep existing
            debugPrint('Duplicate service ignored: ${service.name} (${service.host}:${service.port})');
          }
        }
      } else {
        debugPrint('Service lost: name="${service.name}", host=${service.host}');
        // Remove by host:port combination instead of just name
        _discoveredServices.removeWhere((s) =>
            s.host == service.host && s.port == service.port);
        notifyListeners();
      }
    });
  }

  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await nsd.stopDiscovery(_discovery!);
      _discovery = null;
    }
  }

  void disconnect() {
    _connectedService = null;
    _files = [];
    _relayConnection?.disconnect();
    _relayConnection = null;
    _usingRelay = false;
    notifyListeners();
  }
  
  /// Connect via relay server for internet access
  Future<void> connectViaRelay(String roomId, String passphrase, {String relayUrl = 'ws://192.168.1.3:8081'}) async {
    try {
      debugPrint('Connecting via relay to room: $roomId');
      
      // Derive encryption key
      final salt = EncryptionService.deriveSaltFromPassphrase(passphrase);
      _encryptionKey = EncryptionService.deriveKey(passphrase, salt);
      debugPrint('Encryption key derived for relay connection');
      
      // Connect to relay
      _relayConnection = RelayConnection(relayUrl: relayUrl);
      await _relayConnection!.joinRoom(roomId);
      
      _usingRelay = true;
      
      // Create a fake service for compatibility (but won't be used for HTTP)
      _connectedService = nsd.Service(
        name: 'Internet Connection',
        type: '_http._tcp',
        host: 'relay',  // Not used for actual connection
        port: 0,
      );
      
      debugPrint('Connected via relay');
      notifyListeners();
      
      // Fetch initial files
      await fetchFiles('/');
      
    } catch (e) {
      debugPrint('Failed to connect via relay: $e');
      _relayConnection = null;
      _usingRelay = false;
      rethrow;
    }
  }
  
  // Get saved passphrase for a server
  Future<String?> getSavedPassphrase(nsd.Service service) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'passphrase_${service.host}_${service.port}';
    return prefs.getString(key);
  }
  
  // Save passphrase for a server
  Future<void> savePassphrase(nsd.Service service, String passphrase) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'passphrase_${service.host}_${service.port}';
    await prefs.setString(key, passphrase);
    debugPrint('Saved passphrase for ${service.host}:${service.port}');
  }

  void connectToService(nsd.Service service, {String? passphrase}) {
    _connectedService = service;
    
    debugPrint('connectToService called with passphrase: ${passphrase != null ? "provided (${passphrase.length} chars)" : "null"}');
    
    // Derive encryption key immediately if passphrase is provided
    if (passphrase != null) {
      debugPrint('Deriving salt from passphrase...');
      debugPrint('Passphrase for salt derivation: $passphrase');
      // Derive salt from passphrase (same algorithm as server)
      final salt = EncryptionService.deriveSaltFromPassphrase(passphrase);
      debugPrint('Salt derived: ${salt.length} bytes, hex: ${salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      
      debugPrint('Deriving encryption key...');
      _encryptionKey = EncryptionService.deriveKey(passphrase, salt);
      debugPrint('Encryption key derived: ${_encryptionKey != null ? "${_encryptionKey!.length} bytes" : "null"}');
      if (_encryptionKey != null) {
        debugPrint('Key hex (first 16 bytes): ${_encryptionKey!.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      }
      
      // Save passphrase for future connections
      savePassphrase(service, passphrase);
    } else {
      debugPrint('No passphrase provided - encryption disabled');
      _encryptionKey = null;
    }
    
    notifyListeners();
    fetchFiles('/'); // Initial fetch
  }

  Future<void> fetchFiles(String path) async {
    if (_connectedService == null) {
      debugPrint('fetchFiles called but no service connected');
      return;
    }

    // Check if using relay connection
    if (_usingRelay && _relayConnection != null) {
      await _fetchViaRelay(path);
      return;
    }

    try {
      final uri = Uri.http('${_connectedService!.host}:${_connectedService!.port}', '/files', {'path': path});
      debugPrint('Fetching files from: $uri');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        String bodyText = response.body;
        
        debugPrint('Response headers: ${response.headers}');
        debugPrint('Encryption key present: ${_encryptionKey != null}');
        debugPrint('Response body preview: ${bodyText.substring(0, min(50, bodyText.length))}');
        
        // Check if response is encrypted
        if (response.headers['x-encrypted'] == 'true' && _encryptionKey != null) {
          debugPrint('Attempting to decrypt response...');
          final decrypted = EncryptionService.decryptString(bodyText, _encryptionKey!);
          if (decrypted == null) {
            debugPrint('Failed to decrypt response - wrong passphrase');
            
            // Clear saved passphrase since it's wrong
            if (_connectedService != null) {
              final prefs = await SharedPreferences.getInstance();
              final key = 'passphrase_${_connectedService!.host}_${_connectedService!.port}';
              await prefs.remove(key);
              debugPrint('Cleared invalid passphrase for ${_connectedService!.host}:${_connectedService!.port}');
            }
            
            // Set error state and trigger callback
            _decryptionFailed = true;
            notifyListeners();
            
            // Call the callback immediately if set
            debugPrint('onDecryptionFailed callback registered: ${onDecryptionFailed != null}');
            if (onDecryptionFailed != null) {
              debugPrint('Calling onDecryptionFailed callback...');
              onDecryptionFailed!();
            }
            
            return;
          }
          bodyText = decrypted;
          debugPrint('Successfully decrypted response');
          _decryptionFailed = false;
        } else {
          debugPrint('Response not encrypted or no key available');
        }
        
        final responseData = jsonDecode(bodyText);
        
        // Parse files response
        _parseFilesResponse(responseData);
        
        // Sync tags from server first
        await _syncTagsFromServer();
        
        // Load tags for each file from local database
        for (int i = 0; i < _files.length; i++) {
          final hash = await _tagDb.getHashForPath(_files[i].path);
          
          // Load tags from BOTH path and hash, then merge
          final pathTags = await _tagDb.getTags(_files[i].path);
          final hashTags = hash != null ? await _tagDb.getTags(hash) : <String>[];
          
          // Merge tags (union of both sources)
          final mergedTags = {...pathTags, ...hashTags}.toList();
          
          if (hash != null) {
            _files[i] = _files[i].copyWith(tags: mergedTags, sha256: hash);
          } else {
            _files[i] = _files[i].copyWith(tags: mergedTags);
          }
        }
        
        notifyListeners();
      } else {
        debugPrint('Failed to fetch files: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching files: $e');
    }
  }
  
  Future<void> _fetchViaRelay(String path) async {
    try {
      // Build HTTP request as string
      final requestLine = 'GET /files?path=${Uri.encodeComponent(path)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Sending relay request for path: $path');
      
      // Send through relay
      final responseData = await _relayConnection!.sendRequest(requestData);
      
      // Decode response
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      debugPrint('Received relay response, length: ${bodyText.length}');
      
      // Check if response is encrypted
      if (_encryptionKey != null) {
        debugPrint('Attempting to decrypt relay response...');
        final decrypted = EncryptionService.decryptString(bodyText, _encryptionKey!);
        if (decrypted == null) {
          debugPrint('Failed to decrypt relay response');
          return;
        }
        bodyText = decrypted;
        debugPrint('Successfully decrypted relay response');
      }
      
      final responseData2 = jsonDecode(bodyText);
      _parseFilesResponse(responseData2);
      
      // Sync tags
      await _syncTagsFromServer();
      
      // Load tags for each file
      for (int i = 0; i < _files.length; i++) {
        final hash = await _tagDb.getHashForPath(_files[i].path);
        final pathTags = await _tagDb.getTags(_files[i].path);
        final hashTags = hash != null ? await _tagDb.getTags(hash) : <String>[];
        final mergedTags = {...pathTags, ...hashTags}.toList();
        
        if (hash != null) {
          _files[i] = _files[i].copyWith(tags: mergedTags, sha256: hash);
        } else {
          _files[i] = _files[i].copyWith(tags: mergedTags);
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching via relay: $e');
    }
  }
  
  /// Generic HTTP request via relay
  Future<String?> _httpViaRelay(String method, String path) async {
    if (!_usingRelay || _relayConnection == null) {
      return null;
    }
    
    try {
      // Build HTTP request
      final requestLine = '$method $path HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Sending $method via relay: $path');
      
      // Send through relay
      final responseData = await _relayConnection!.sendRequest(requestData);
      
      // Decode response
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      // Decrypt if needed
      if (_encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(bodyText, _encryptionKey!);
        if (decrypted == null) {
          debugPrint('Failed to decrypt relay response for $path');
          return null;
        }
        bodyText = decrypted;
      }
      
      return bodyText;
    } catch (e) {
      debugPrint('Error in HTTP via relay: $e');
      return null;
    }
  }
  
  void _parseFilesResponse(dynamic responseData) {
    // Try to parse as new format {rootPath, files} or fallback to old format
    if (responseData is Map<String, dynamic> && responseData.containsKey('files')) {
      // New format
      _serverRootPath = responseData['rootPath'];
      final List<dynamic> json = responseData['files'];
      _files = json.map((e) => FileItem.fromJson(e)).toList();
    } else {
      // Old format (backwards compatibility)
      final List<dynamic> json = responseData;
      _files = json.map((e) => FileItem.fromJson(e)).toList();
    }
  }

  String getStreamUrl(String filePath) {
    if (_connectedService == null) return '';
    return 'http://${_connectedService!.host}:${_connectedService!.port}/stream?path=${Uri.encodeComponent(filePath)}';
  }

  // Cache for relay thumbnails (path -> image bytes)
    // Check cache first
    if (_relayThumbnailCache.containsKey(filePath)) {
      return _relayThumbnailCache[filePath];
    }
    
    try {
      // Build HTTP request for thumbnail
      final requestLine = 'GET /thumbnail?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching thumbnail via relay: $filePath');
      
      // Send through relay
      final responseData = await _relayConnection!.sendRequest(requestData);
      
      // Decode response - thumbnails are binary, not encrypted
      final thumbnailBytes = base64.decode(responseData);
      
      // Cache it
      _relayThumbnailCache[filePath] = thumbnailBytes;
      
      return thumbnailBytes;
    } catch (e) {
      debugPrint('Error fetching thumbnail via relay: $e');
      return null;
    }
  }
  
  /// Get full file bytes for relay mode (images/videos)
  Future<Uint8List?> getStreamBytes(String filePath) async {
    if (!_usingRelay) return null;
    
    try {
      // Build HTTP request for streaming
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      debugPrint('Fetching file via relay: $filePath');
      
      // Send through relay
      final responseData = await _relayConnection!.sendRequest(requestData);
      
      // Decode response - files are binary, not encrypted
      final fileBytes = base64.decode(responseData);
      
      debugPrint('Received file via relay: ${fileBytes.length} bytes');
      
      return fileBytes;
    } catch (e) {
      debugPrint('Error fetching file via relay: $e');
      return null;
    }
  }

  Future<bool> createFolder(String currentPath, String folderName) async {
    if (_connectedService == null) return false;

    try {
      final url = 'http://${_connectedService!.host}:${_connectedService!.port}/create';
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
        await fetchFiles(currentPath); // Refresh
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return false;
    }
  }

  Future<bool> createTextFile(String currentPath, String fileName) async {
    if (_connectedService == null) return false;

    try {
      final url = 'http://${_connectedService!.host}:${_connectedService!.port}/create';
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
        await fetchFiles(currentPath); // Refresh
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error creating text file: $e');
      return false;
    }
  }


  Future<bool> deleteItem(String path, String currentPath) async {
    if (_connectedService == null) return false;

    try {
      final url = 'http://${_connectedService!.host}:${_connectedService!.port}/delete';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      );

      if (response.statusCode == 200) {
        await fetchFiles(currentPath); // Refresh
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting item: $e');
      return false;
    }
  }

  Future<bool> renameItem(String oldPath, String newName, String currentPath) async {
    if (_connectedService == null) return false;

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
        // No separator found - shouldn't happen but handle it
        directory = '';
      } else if (separatorIndex == 0) {
        // Unix root directory
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

      final url = 'http://${_connectedService!.host}:${_connectedService!.port}/move';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPath': oldPath,
          'newPath': newPath,
        }),
      );

      if (response.statusCode == 200) {
        await fetchFiles(currentPath); // Refresh
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error renaming item: $e');
      return false;
    }
  }

  Future<bool> moveItem(String oldPath, String newPath, String currentPath) async {
    if (_connectedService == null) return false;

    try {
      final url = 'http://${_connectedService!.host}:${_connectedService!.port}/move';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPath': oldPath,
          'newPath': newPath,
        }),
      );

      if (response.statusCode == 200) {
        await fetchFiles(currentPath); // Refresh
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error moving item: $e');
      return false;
    }
  }

  Future<bool> uploadFile(String filePath, String remotePath, String fileName) async {
    if (_connectedService == null) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final url = 'http://${_connectedService!.host}:${_connectedService!.port}/upload?path=${Uri.encodeComponent(remotePath)}&filename=${Uri.encodeComponent(fileName)}';
      
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
        await fetchFiles(remotePath); // Refresh
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return false;
    }
  }
  
  // Tag management methods
  Future<void> addTagToFile(String path, String tag, String currentPath) async {
    // Get or compute hash for file
    String? hash = await _tagDb.getHashForPath(path);
    
    if (hash == null) {
      // Need to compute hash - for remote files, we skip this for now
      // In a real implementation, you'd download and hash the file
      debugPrint('Cannot add tag: hash not found for $path');
      return;
    }
    
    await _tagDb.addTag(hash, tag);
    await fetchFiles(currentPath); // Refresh to show new tags
  }
  
  Future<void> removeTagFromFile(String path, String tag, String currentPath) async {
    final hash = await _tagDb.getHashForPath(path);
    if (hash != null) {
      await _tagDb.removeTag(hash, tag);
      await fetchFiles(currentPath); // Refresh to show updated tags
    }
  }
  
  Future<List<String>> getAllTags() async {
    return await _tagDb.getAllTags();
  }
  
  /// Ensures a file has a hash computed, without modifying tags
  /// Returns the hash if successful, or error information
  Future<Map<String, dynamic>> ensureFileHasHash(String path) async {
    // Check if hash already exists
    String? hash = await _tagDb.getHashForPath(path);
    
    if (hash != null) {
      return {'success': true, 'hash': hash};
    }
    
    // Hash doesn't exist, request it from server
    try {
      if (_connectedService == null) {
        return {'success': false, 'error': 'Not connected to any server'};
      }

      final host = _connectedService!.host;
      final port = _connectedService!.port;
      
      final uri = Uri.http('$host:$port', '/file-hash', {'path': path});
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        hash = data['hash'] as String;
        final size = data['size'] as int;
        final modified = data['modified'] as int;
        
        // Store hash in database (but don't touch tags!)
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
    {bool refresh = true} // Add optional parameter to control refresh
  ) async {
    debugPrint('===== updateFileTags called =====');
    debugPrint('Path: $path');
    debugPrint('New tags: $newTags');
    debugPrint('Refresh: $refresh');
    
    String? hash = await _tagDb.getHashForPath(path);
    debugPrint('Hash from database: $hash');
    
    // Trigger hash computation in background if needed
    if (hash == null) {
      debugPrint('No hash found, triggering background hash computation');
      _computeHashInBackground(path);
    }
    
    try {
      // Load existing tags from BOTH path and hash (if available)
      final pathTags = await _tagDb.getTags(path);
      final hashTags = hash != null ? await _tagDb.getTags(hash) : <String>[];
      
      // Merge to get current tag set (union)
      final currentTags = {...pathTags, ...hashTags}.toList();
      debugPrint('Current tags from path: $pathTags');
      debugPrint('Current tags from hash: $hashTags');
      debugPrint('Merged current tags: $currentTags');
      
      // Update tags stored under PATH
      for (final tag in currentTags) {
        if (!newTags.contains(tag)) {
          debugPrint('Removing tag from path index: $tag');
          await _tagDb.removeTag(path, tag);
        }
      }
      for (final tag in newTags) {
        if (!pathTags.contains(tag)) {
          debugPrint('Adding tag to path index: $tag');
          await _tagDb.addTag(path, tag);
        }
      }
      
      // Also update tags stored under HASH (if available)
      if (hash != null && hash != path) {
        for (final tag in currentTags) {
          if (!newTags.contains(tag)) {
            debugPrint('Removing tag from hash index: $tag');
            await _tagDb.removeTag(hash, tag);
          }
        }
        for (final tag in newTags) {
          if (!hashTags.contains(tag)) {
            debugPrint('Adding tag to hash index: $tag');
            await _tagDb.addTag(hash, tag);
          }
        }
      }
      
      // Verify tags were saved
      final savedPathTags = await _tagDb.getTags(path);
      final savedHashTags = hash != null ? await _tagDb.getTags(hash) : <String>[];
      debugPrint('Tags after save - path: $savedPathTags, hash: $savedHashTags');
      
      // Push changes to server (use hash if available, otherwise path)
      final syncKey = hash ?? path;
      final syncResult = await _syncTagsToServer(syncKey, newTags);
      if (!syncResult['success']) {
        return {'success': false, 'error': 'Tags saved locally but sync failed: ${syncResult['error']}'};
      }
      
      // Only refresh if requested
      if (refresh) {
        debugPrint('Refreshing file list...');
        await fetchFiles(currentPath);
      }
      debugPrint('===== updateFileTags completed successfully =====');
      return {'success': true};
    } catch (e) {
      debugPrint('Error in updateFileTags: $e');
      return {'success': false, 'error': 'Error updating tags in database: $e'};
    }
  }
  
  // Compute hash in background and sync tags to hash index when ready
  void _computeHashInBackground(String path) {
    debugPrint('Starting background hash computation for: $path');
    ensureFileHasHash(path).then((result) {
      if (result['success']) {
        final realHash = result['hash'] as String;
        debugPrint('Background hash computed: $path → $realHash');
        
        // Sync tags from path to hash index
        _syncTagsToHashIndex(path, realHash);
      } else {
        debugPrint('Background hash computation failed: ${result['error']}');
      }
    }).catchError((e) {
      debugPrint('Error in background hash computation: $e');
    });
  }
  
  // Sync tags from path index to hash index (both indices keep tags)
  Future<void> _syncTagsToHashIndex(String path, String hash) async {
    if (path == hash) return;
    
    debugPrint('Syncing tags from path to hash index: $path → $hash');
    
    try {
      // Get tags stored under path
      final pathTags = await _tagDb.getTags(path);
      final hashTags = await _tagDb.getTags(hash);
      
      // Copy any path tags that aren't already in hash index
      if (pathTags.isNotEmpty) {
        for (final tag in pathTags) {
          if (!hashTags.contains(tag)) {
            await _tagDb.addTag(hash, tag);
            debugPrint('Synced tag to hash index: $tag');
          }
        }
        
        debugPrint('Synced ${pathTags.length} tags from path to hash index');
      }
    } catch (e) {
      debugPrint('Error syncing tags to hash index: $e');
    }
  }
  
  // Tag synchronization methods
  Future<Map<String, dynamic>> _syncTagsToServer(String hash, List<String> tags) async {
    if (_connectedService == null) {
      return {'success': false, 'error': 'Not connected to server'};
    }
    
    try {
      final host = _connectedService!.host;
      final port = _connectedService!.port;
      
      // Get current tags from server
      final getUri = Uri.http('$host:$port', '/tags/$hash');
      final getResponse = await http.get(getUri);
      
      List<String> serverTags = [];
      if (getResponse.statusCode == 200) {
        final data = jsonDecode(getResponse.body);
        serverTags = List<String>.from(data['tags'] ?? []);
      }
      
      // Determine tags to add and remove
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
          return {'success': false, 'error': 'Failed to add tag "$tag" to server (HTTP ${response.statusCode})'};
        }
        debugPrint('Synced tag to server: $tag');
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
          return {'success': false, 'error': 'Failed to remove tag "$tag" from server (HTTP ${response.statusCode})'};
        }
        debugPrint('Removed tag from server: $tag');
      }
      
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': 'Network error while syncing: $e'};
    }
  }
  
  Future<void> _syncTagsFromServer() async {
    if (_connectedService == null) return;
    
    try {
      String? responseBody;
      
      // Use relay or direct HTTP depending on connection mode
      if (_usingRelay) {
        debugPrint('Syncing tags via relay...');
        responseBody = await _httpViaRelay('GET', '/tags/all-hashes');
      } else {
        final host = _connectedService!.host;
        final port = _connectedService!.port;
        
        // Get all hash->tags from server
        final uri = Uri.http('$host:$port', '/tags/all-hashes');
        final response = await http.get(uri);
        
        if (response.statusCode == 200) {
          responseBody = response.body;
          
          // Decrypt if encrypted
          if (response.headers['x-encrypted'] == 'true' && _encryptionKey != null) {
            responseBody = EncryptionService.decryptString(responseBody, _encryptionKey!);
          }
        }
      }
      
      if (responseBody == null) return;
      
      final data = jsonDecode(responseBody);
      final hashTagsMap = Map<String, List<dynamic>>.from(data['hashTags'] ?? {});
      
      // Merge with local database (server wins)
      for (final entry in hashTagsMap.entries) {
        final hash = entry.key;
        final serverTags = List<String>.from(entry.value);
        
        // Get current local tags
        final localTags = await _tagDb.getTags(hash);
        
        // Remove local tags not on server
        for (final tag in localTags) {
          if (!serverTags.contains(tag)) {
            await _tagDb.removeTag(hash, tag);
          }
        }
        
        // Add server tags not in local
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
