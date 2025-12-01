import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_item.dart';
import '../crypto/encryption_service.dart';
import '../relay/relay_connection.dart';
import '../relay/local_proxy_server.dart';

/// Manages file browsing, listing, and relay operations
class FileBrowserManager with ChangeNotifier {
  List<FileItem> _files = [];
  List<FileItem> get files => _files;
  
  String? _serverRootPath;
  String? get serverRootPath => _serverRootPath;
  
  // Relay thumbnail cache
  final Map<String, Uint8List> _relayThumbnailCache = {};
  
  // Local proxy server for video streaming
  LocalProxyServer? _proxyServer;
  
  final nsd.Service? Function() _getConnectedService;
  final bool Function() _isUsingRelay;
  final RelayConnection? Function() _getRelayConnection;
  final Uint8List? Function() _getEncryptionKey;
  final Future<void> Function() _syncTagsFromServer;
  final Future<List<String>> Function(String path) _getTagsForPath;
  final Future<String?> Function(String path) _getHashForPath;
  final void Function(bool failed) _setDecryptionFailed;
  final Function()? Function() _getOnDecryptionFailedCallback;
  
  FileBrowserManager({
    required nsd.Service? Function() getConnectedService,
    required bool Function() isUsingRelay,
    required RelayConnection? Function() getRelayConnection,
    required Uint8List? Function() getEncryptionKey,
    required Future<void> Function() syncTagsFromServer,
    required Future<List<String>> Function(String path) getTagsForPath,
    required Future<String?> Function(String path) getHashForPath,
    required void Function(bool failed) setDecryptionFailed,
    required Function()? Function() getOnDecryptionFailedCallback,
  })  : _getConnectedService = getConnectedService,
        _isUsingRelay = isUsingRelay,
        _getRelayConnection = getRelayConnection,
        _getEncryptionKey = getEncryptionKey,
        _syncTagsFromServer = syncTagsFromServer,
        _getTagsForPath = getTagsForPath,
        _getHashForPath = getHashForPath,
        _setDecryptionFailed = setDecryptionFailed,
        _getOnDecryptionFailedCallback = getOnDecryptionFailedCallback;

  Future<void> fetchFiles(String path) async {
    final service = _getConnectedService();
    if (service == null) {
      debugPrint('fetchFiles called but no service connected');
      return;
    }

    if (_isUsingRelay()) {
      await _fetchViaRelay(path);
      return;
    }

    try {
      final uri = Uri.http('${service.host}:${service.port}', '/files', {'path': path});
      debugPrint('Fetching files from: $uri');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        String bodyText = response.body;
        
        final encryptionKey = _getEncryptionKey();
        if (response.headers['x-encrypted'] == 'true' && encryptionKey != null) {
          final decrypted = EncryptionService.decryptString(bodyText, encryptionKey);
          if (decrypted == null) {
            debugPrint('Failed to decrypt response - wrong passphrase');
            
            // Clear saved passphrase
            final prefs = await SharedPreferences.getInstance();
            final key = 'passphrase_${service.host}_${service.port}';
            await prefs.remove(key);
            
            _setDecryptionFailed(true);
            notifyListeners();
            
            final callback = _getOnDecryptionFailedCallback();
            if (callback != null) {
              callback();
            }
            return;
          }
          bodyText = decrypted;
          _setDecryptionFailed(false);
        }
        
        final responseData = jsonDecode(bodyText);
        _parseFilesResponse(responseData);
        
        await _syncTagsFromServer();
        await _loadTagsForFiles();
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching files: $e');
    }
  }
  
  Future<void> _fetchViaRelay(String path) async {
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return;
    
    try {
      final requestLine = 'GET /files?path=${Uri.encodeComponent(path)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      final encryptionKey = _getEncryptionKey();
      if (encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(bodyText, encryptionKey);
        if (decrypted == null) {
          debugPrint('Failed to decrypt relay response');
          return;
        }
        bodyText = decrypted;
      }
      
      final responseData2 = jsonDecode(bodyText);
      _parseFilesResponse(responseData2);
      
      await _syncTagsFromServer();
      await _loadTagsForFiles();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching via relay: $e');
    }
  }
  
  Future<void> _loadTagsForFiles() async {
    for (int i = 0; i < _files.length; i++) {
      final hash = await _getHashForPath(_files[i].path);
      final pathTags = await _getTagsForPath(_files[i].path);
      final hashTags = hash != null ? await _getTagsForPath(hash) : <String>[];
      final mergedTags = {...pathTags, ...hashTags}.toList();
      
      if (hash != null) {
        _files[i] = _files[i].copyWith(tags: mergedTags, sha256: hash);
      } else {
        _files[i] = _files[i].copyWith(tags: mergedTags);
      }
    }
  }
  
  void _parseFilesResponse(dynamic responseData) {
    if (responseData is Map<String, dynamic> && responseData.containsKey('files')) {
      _serverRootPath = responseData['rootPath'];
      final List<dynamic> json = responseData['files'];
      _files = json.map((e) => FileItem.fromJson(e)).toList();
    } else {
      final List<dynamic> json = responseData;
      _files = json.map((e) => FileItem.fromJson(e)).toList();
    }
  }

  String getStreamUrl(String filePath) {
    final service = _getConnectedService();
    if (service == null) return '';
    
    if (_isUsingRelay()) {
      return 'relay:stream:${Uri.encodeComponent(filePath)}';
    }
    
    return 'http://${service.host}:${service.port}/stream?path=${Uri.encodeComponent(filePath)}';
  }
  
  String getThumbnailUrl(String filePath) {
    final service = _getConnectedService();
    if (service == null) return '';
    
    if (_isUsingRelay()) {
      return 'relay:thumbnail:${Uri.encodeComponent(filePath)}';
    }
    
    return 'http://${service.host}:${service.port}/thumbnail?path=${Uri.encodeComponent(filePath)}';
  }
  
  Future<Uint8List?> getThumbnailBytes(String filePath) async {
    if (!_isUsingRelay()) return null;
    
    if (_relayThumbnailCache.containsKey(filePath)) {
      return _relayThumbnailCache[filePath];
    }
    
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /thumbnail?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final thumbnailBytes = base64.decode(responseData);
      
      _relayThumbnailCache[filePath] = thumbnailBytes;
      return thumbnailBytes;
    } catch (e) {
      debugPrint('Error fetching thumbnail via relay: $e');
      return null;
    }
  }
  
  Future<Uint8List?> getStreamBytes(String filePath) async {
    if (!_isUsingRelay()) return null;
    
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = 'GET /stream?path=${Uri.encodeComponent(filePath)} HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final fileBytes = base64.decode(responseData);
      
      debugPrint('Received file via relay: ${fileBytes.length} bytes');
      return fileBytes;
    } catch (e) {
      debugPrint('Error fetching file via relay: $e');
      return null;
    }
  }
  
  Future<String?> httpViaRelay(String method, String path) async {
    if (!_isUsingRelay()) return null;
    
    final relayConnection = _getRelayConnection();
    if (relayConnection == null) return null;
    
    try {
      final requestLine = '$method $path HTTP/1.1\r\n\r\n';
      final requestData = base64.encode(utf8.encode(requestLine));
      
      final responseData = await relayConnection.sendRequest(requestData);
      final responseBytes = base64.decode(responseData);
      String bodyText = utf8.decode(responseBytes);
      
      final encryptionKey = _getEncryptionKey();
      if (encryptionKey != null) {
        final decrypted = EncryptionService.decryptString(bodyText, encryptionKey);
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
  
  /// Start local proxy server for video streaming over relay
  Future<void> startProxyServer() async {
    if (_proxyServer != null) return; // Already running
    
    if (!_isUsingRelay()) return; // Only needed for relay
    
    try {
      _proxyServer = LocalProxyServer(
        fetchViaRelay: (path) => getStreamBytes(path),
      );
      
      final baseUrl = await _proxyServer!.start();
      debugPrint('Local proxy server started: $baseUrl');
    } catch (e) {
      debugPrint('Failed to start proxy server: $e');
    }
  }
  
  /// Stop local proxy server
  Future<void> stopProxyServer() async {
    if (_proxyServer != null) {
      await _proxyServer!.stop();
      _proxyServer = null;
      debugPrint('Local proxy server stopped');
    }
  }
  
  /// Get proxy URL for video file (for media players)
  String? getProxyUrl(String filePath) {
    if (_proxyServer == null) return null;
    return _proxyServer!.getProxyUrl(filePath);
  }
  
  @override
  void dispose() {
    stopProxyServer();
    super.dispose();
  }
}
