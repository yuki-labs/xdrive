import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../storage/tag_database.dart';
import 'utils/thumbnail_generator.dart';
import 'request_handlers/file_handlers.dart';
import 'request_handlers/tag_handlers.dart';
import 'request_handlers/file_operations_handlers.dart';
import 'encryption_manager.dart';
import 'relay_mode_manager.dart';
import 'relay_request_handler.dart';

/// Main HTTP file server using helper managers
class FileServer {
  HttpServer? _server;
  final int port;
  String? _rootDirectory;
  final TagDatabase _tagDb = TagDatabase();
  
  // Managers
  final EncryptionManager _encryptionManager = EncryptionManager();
  final RelayModeManager _relayModeManager = RelayModeManager();
  
  // Handlers
  late final ThumbnailGenerator _thumbnailGenerator;
  late final FileHandlers _fileHandlers;
  late final TagHandlers _tagHandlers;
  late final FileOperationsHandlers _fileOpsHandlers;
  late final RelayRequestHandler _relayRequestHandler;
  
  bool get relayMode => _relayModeManager.relayMode;
  String? get relayRoomId => _relayModeManager.relayRoomId;
  String? get passphrase => _encryptionManager.passphrase;
  
  FileServer({this.port = 8080}) {
    _thumbnailGenerator = ThumbnailGenerator();
  }

  Future<void> start({String? rootDirectory}) async {
    _rootDirectory = rootDirectory;
    
    // Initialize encryption
    await _encryptionManager.initialize();
    
    // Initialize handlers
    _fileHandlers = FileHandlers(
      rootDirectory: _rootDirectory,
      encryptionKey: _encryptionManager.encryptionKey,
      thumbnailGenerator: _thumbnailGenerator,
    );
    
    _tagHandlers = TagHandlers(
      tagDb: _tagDb,
      encryptionKey: _encryptionManager.encryptionKey,
    );
    
    _fileOpsHandlers = FileOperationsHandlers(rootDirectory: _rootDirectory);
    
    _relayRequestHandler = RelayRequestHandler(
      fileHandlers: _fileHandlers,
      tagHandlers: _tagHandlers,
      sendResponse: (requestId, data) =>
          _relayModeManager.relayClient?.sendResponse(requestId, data),
    );
    
    // Setup router
    final router = _setupRouter();
    
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    debugPrint('Server running on port ${_server!.port}');
    if (_rootDirectory != null) {
      debugPrint('Serving files from: $_rootDirectory');
    }
  }

  Router _setupRouter() {
    final router = Router();

    // File handlers
    router.get('/files', (Request request) => _fileHandlers.handleGetFiles(request));
    router.get('/stream', (Request request) => _fileHandlers.handleStreamFile(request));
    router.get('/thumbnail', (Request request) => _fileHandlers.handleGetThumbnail(request));
    
    // File operations
    router.get('/file-hash', (Request request) => _fileOpsHandlers.handleGetFileHash(request));
    router.post('/create', (Request request) => _fileOpsHandlers.handleCreateItem(request));
    router.post('/delete', (Request request) => _fileOpsHandlers.handleDeleteItem(request));
    router.post('/move', (Request request) => _fileOpsHandlers.handleMoveItem(request));
    router.post('/upload', (Request request) => _fileOpsHandlers.handleUploadFile(request));
    
    // Tag handlers
    router.get('/tags/<hash>', (Request request, String hash) =>
        _tagHandlers.handleGetTagsForHash(request, hash));
    router.post('/tags/add', (Request request) => _tagHandlers.handleAddTag(request));
    router.post('/tags/remove', (Request request) => _tagHandlers.handleRemoveTag(request));
    router.get('/tags/all-hashes', (Request request) =>
        _tagHandlers.handleGetAllTaggedHashes(request));

    return router;
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    await _relayModeManager.disableRelayMode();
  }
  
  /// Enable relay mode for internet access
  Future<String> enableRelayMode({String relayUrl = 'ws://127.0.0.1:8081'}) async {
    return await _relayModeManager.enableRelayMode(
      relayUrl: relayUrl,
      requestHandler: _relayRequestHandler,
    );
  }
  
  /// Disable relay mode
  Future<void> disableRelayMode() async {
    await _relayModeManager.disableRelayMode();
  }

  void updateRootDirectory(String newRootDirectory) {
    _rootDirectory = newRootDirectory;
    debugPrint('Updated server root directory to: $newRootDirectory');
  }
  
  Future<void> regeneratePassphrase() async {
    await _encryptionManager.regeneratePassphrase();
  }
}
