import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import '../models/file_item.dart';
import 'connection_manager.dart';
import 'file_operations_manager.dart';
import 'tag_manager.dart';
import 'file_browser_manager.dart';

/// Main provider that coordinates all file operations
/// This is a thin coordinator that delegates to specialized managers
class RemoteFileProvider with ChangeNotifier {
  // Managers
  late final ConnectionManager _connection;
  late final FileOperationsManager _operations;
  late final TagManager _tags;
  late final FileBrowserManager _browser;
  
  RemoteFileProvider() {
    // Initialize connection manager
    _connection = ConnectionManager();
    
    // Initialize file operations manager
    _operations = FileOperationsManager(
      getConnectedService: () => _connection.connectedService,
      refreshFiles: (path) async {
        await _browser.fetchFiles(path);
        notifyListeners();
      },
    );
    
    // Initialize tag manager  
    _tags = TagManager(
      getConnectedService: () => _connection.connectedService,
      refreshFiles: (path) async {
        await _browser.fetchFiles(path);
        notifyListeners();
      },
      isUsingRelay: () => _connection.usingRelay,
      httpViaRelay: (method, path) => _browser.httpViaRelay(method, path),
      getEncryptionKey: () => _connection.encryptionKey,
    );
    
    // Initialize browser manager
    _browser = FileBrowserManager(
      getConnectedService: () => _connection.connectedService,
      isUsingRelay: () => _connection.usingRelay,
      getRelayConnection: () => _connection.relayConnection,
      getEncryptionKey: () => _connection.encryptionKey,
      syncTagsFromServer: () => _tags.syncTagsFromServer(),
      getTagsForPath: (path) => _tags.getTagsForPath(path),
      getHashForPath: (path) => _tags.getHashForPath(path),
      setDecryptionFailed: (failed) => _connection.setDecryptionFailed(failed),
      getOnDecryptionFailedCallback: () => _connection.onDecryptionFailed,
    );
    
    // Forward notifications from managers
    _connection.addListener(_notifyAll);
    _browser.addListener(_notifyAll);
  }
  
  void _notifyAll() {
    notifyListeners();
  }
  
  @override
  void dispose() {
    _connection.removeListener(_notifyAll);
    _browser.removeListener(_notifyAll);
    _connection.dispose();
    _browser.dispose();
    super.dispose();
  }
  
  // === Discovery and Connection ===
  
  List<nsd.Service> get discoveredServices => _connection.discoveredServices;
  nsd.Service? get connectedService => _connection.connectedService;
  bool get decryptionFailed => _connection.decryptionFailed;
  set onDecryptionFailed(Function()? callback) => _connection.onDecryptionFailed = callback;
  
  Future<void> startDiscovery() => _connection.startDiscovery();
  Future<void> stopDiscovery() => _connection.stopDiscovery();
  void disconnect() {
    _connection.disconnect();
    notifyListeners();
  }
  
  Future<void> connectViaRelay(String roomId, String passphrase, {String relayUrl = 'wss://xdrive-production.up.railway.app'}) async {
    await _connection.connectViaRelay(roomId, passphrase, relayUrl: relayUrl);
    // Start proxy server for video streaming
    await _browser.startProxyServer();
    // Fetch initial files after relay connection
    await _browser.fetchFiles('/');
    notifyListeners();
  }
  
  /// Connect via relay using username (new method)
  Future<List<String>> connectViaUsername(String username, String passphrase, {String relayUrl = 'wss://xdrive-production.up.railway.app'}) async {
    final hosts = await _connection.connectViaUsername(username, passphrase, relayUrl: relayUrl);
    
    // If only one host, auto-connected - start proxy and fetch files
    if (hosts.length == 1) {
      await _browser.startProxyServer();
      await _browser.fetchFiles('/');
      notifyListeners();
    }
    
    return hosts;
  }
  
  /// Select a specific host to connect to (after connectViaUsername)
  Future<void> selectHost(String deviceName) async {
    await _connection.selectHost(deviceName);
    // Now connected - start proxy and fetch files
    await _browser.startProxyServer();
    await _browser.fetchFiles('/');
    notifyListeners();
  }
  
  Future<String?> getSavedPassphrase(nsd.Service service) => _connection.getSavedPassphrase(service);
  Future<void> savePassphrase(nsd.Service service, String passphrase) => _connection.savePassphrase(service, passphrase);
  
  void connectToService(nsd.Service service, {String? passphrase}) {
    _connection.connectToService(service, passphrase: passphrase);
    _browser.fetchFiles('/'); // Initial fetch
  }
  
  // === File Browsing ===
  
  List<FileItem> get files => _browser.files;
  String? get serverRootPath => _browser.serverRootPath;
  
  Future<void> fetchFiles(String path) async {
    await _browser.fetchFiles(path);
    notifyListeners();
  }
  
  String getStreamUrl(String filePath) => _browser.getStreamUrl(filePath);
  String getThumbnailUrl(String filePath) => _browser.getThumbnailUrl(filePath);
  Future<Uint8List?> getThumbnailBytes(String filePath) => _browser.getThumbnailBytes(filePath);
  Future<Uint8List?> getStreamBytes(String filePath) => _browser.getStreamBytes(filePath);
  String? getProxyUrl(String filePath) => _browser.getProxyUrl(filePath);
  
  // === File Operations ===
  
  Future<bool> createFolder(String currentPath, String folderName) => 
      _operations.createFolder(currentPath, folderName);
      
  Future<bool> createTextFile(String currentPath, String fileName) => 
      _operations.createTextFile(currentPath, fileName);
      
  Future<bool> deleteItem(String path, String currentPath) => 
      _operations.deleteItem(path, currentPath);
      
  Future<bool> renameItem(String oldPath, String newName, String currentPath) => 
      _operations.renameItem(oldPath, newName, currentPath);
      
  Future<bool> moveItem(String oldPath, String newPath, String currentPath) => 
      _operations.moveItem(oldPath, newPath, currentPath);
      
  Future<bool> uploadFile(String filePath, String remotePath, String fileName) => 
      _operations.uploadFile(filePath, remotePath, fileName);
  
  // === Tag Management ===
  
  Future<void> addTagToFile(String path, String tag, String currentPath) => 
      _tags.addTagToFile(path, tag, currentPath);
      
  Future<void> removeTagFromFile(String path, String tag, String currentPath) => 
      _tags.removeTagFromFile(path, tag, currentPath);
      
  Future<List<String>> getAllTags() => _tags.getAllTags();
  
  Future<Map<String, dynamic>> ensureFileHasHash(String path) => 
      _tags.ensureFileHasHash(path);
      
  Future<Map<String, dynamic>> updateFileTags(
    String path,
    List<String> newTags,
    String currentPath,
    {bool refresh = true}
  ) => _tags.updateFileTags(path, newTags, currentPath, refresh: refresh);
}
