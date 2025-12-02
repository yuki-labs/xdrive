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
import 'proxy_manager.dart';
import 'relay_file_helper.dart';

/// Manages file browsing using helpers for relay and proxy
class FileBrowserManager with ChangeNotifier {
  List<FileItem> _files = [];
  List<FileItem> get files => _files;
  
  String? _serverRootPath;
  String? get serverRootPath => _serverRootPath;
  
  // Helpers
  late final ProxyManager _proxyManager;
  late final RelayFileHelper _relayHelper;
  
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
        _getOnDecryptionFailedCallback = getOnDecryptionFailedCallback {
    // Initialize helpers
    _proxyManager = ProxyManager(
      getRelayConnection: getRelayConnection,
      isUsingRelay: isUsingRelay,
      getEncryptionKey: getEncryptionKey,
    );
    _relayHelper = RelayFileHelper(
      getRelayConnection: getRelayConnection,
      getEncryptionKey: getEncryptionKey,
    );
  }

  Future<void> fetchFiles(String path) async {
    final service = _getConnectedService();
    if (service == null) return;

    if (_isUsingRelay()) {
      await _fetchViaRelay(path);
      return;
    }

    try {
      final uri = Uri.http('${service.host}:${service.port}', '/files', {'path': path});
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        String bodyText = response.body;
        
        final encryptionKey = _getEncryptionKey();
        if (response.headers['x-encrypted'] == 'true' && encryptionKey != null) {
          final decrypted = EncryptionService.decryptString(bodyText, encryptionKey);
          if (decrypted == null) {
            // Handle decryption failure
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('passphrase_${service.host}_${service.port}');
            _setDecryptionFailed(true);
            notifyListeners();
            final callback = _getOnDecryptionFailedCallback();
            callback?.call();
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
    final bodyText = await _relayHelper.fetchFilesViaRelay(path);
    if (bodyText == null) return;
    
    final responseData = jsonDecode(bodyText);
    _parseFilesResponse(responseData);
    await _syncTagsFromServer();
    await _loadTagsForFiles();
    notifyListeners();
  }
  
  Future<void> _loadTagsForFiles() async {
    for (int i = 0; i < _files.length; i++) {
      final hash = await _getHashForPath(_files[i].path);
      final pathTags = await _getTagsForPath(_files[i].path);
      final hashTags = hash != null ? await _getTagsForPath(hash) : <String>[];
      final mergedTags = {...pathTags, ...hashTags}.toList();
      
      _files[i] = hash != null
          ? _files[i].copyWith(tags: mergedTags, sha256: hash)
          : _files[i].copyWith(tags: mergedTags);
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
  
  // Delegate to helpers
  Future<Uint8List?> getThumbnailBytes(String filePath) =>
      _isUsingRelay() ? _relayHelper.getThumbnailBytes(filePath) : Future.value(null);
  
  Future<Uint8List?> getStreamBytes(String filePath) =>
      _isUsingRelay() ? _relayHelper.getStreamBytes(filePath) : Future.value(null);
  
  Future<String?> httpViaRelay(String method, String path) =>
      _relayHelper.httpViaRelay(method, path);
  
  Future<void> startProxyServer() => _proxyManager.startProxyServer();
  Future<void> stopProxyServer() => _proxyManager.stopProxyServer();
  String? getProxyUrl(String filePath) => _proxyManager.getProxyUrl(filePath);
  
  @override
  void dispose() {
    stopProxyServer();
    super.dispose();
  }
}
