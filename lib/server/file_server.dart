import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../models/file_item.dart';
import '../storage/tag_database.dart';
import '../crypto/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../relay/relay_client.dart';
import 'utils/thumbnail_generator.dart';
import 'request_handlers/file_handlers.dart';
import 'request_handlers/tag_handlers.dart';
import 'request_handlers/file_operations_handlers.dart';

/// Main HTTP file server with encryption and relay support
class FileServer {
  HttpServer? _server;
  final int port;
  String? _rootDirectory;
  final TagDatabase _tagDb = TagDatabase();
  
  // Encryption fields
  String? _passphrase;
  Uint8List? _salt;
  Uint8List? _encryptionKey;
  
  // Relay fields
  RelayClient? _relayClient;
  bool _relayMode = false;
  
  // Handler instances
  late final ThumbnailGenerator _thumbnailGenerator;
  late final FileHandlers _fileHandlers;
  late final TagHandlers _tagHandlers;
  late final FileOperationsHandlers _fileOpsHandlers;
  
  bool get relayMode => _relayMode;
  String? get relayRoomId => _relayClient?.roomId;

  FileServer({this.port = 8080}) {
    _thumbnailGenerator = ThumbnailGenerator();
  }

  Future<void> start({String? rootDirectory}) async {
    _rootDirectory = rootDirectory;
    
    // Initialize encryption
    await _initializeEncryption();
    
    // Initialize handlers
    _fileHandlers = FileHandlers(
      rootDirectory: _rootDirectory,
      encryptionKey: _encryptionKey,
      thumbnailGenerator: _thumbnailGenerator,
    );
    
    _tagHandlers = TagHandlers(tagDb: _tagDb, encryptionKey: _encryptionKey);
    _fileOpsHandlers = FileOperationsHandlers(rootDirectory: _rootDirectory);
    
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

  Future<void> _initializeEncryption() async {
    final prefs = await SharedPreferences.getInstance();
    _passphrase = prefs.getString('server_passphrase');
    
    if (_passphrase == null) {
      _passphrase = EncryptionService.generatePassphrase();
      await prefs.setString('server_passphrase', _passphrase!);
      debugPrint('Generated new server passphrase: $_passphrase');
    } else {
      debugPrint('Loaded existing server passphrase: $_passphrase');
    }
    
    debugPrint('Server deriving salt from passphrase: $_passphrase');
    _salt = EncryptionService.deriveSaltFromPassphrase(_passphrase!);
    debugPrint('Server salt: ${_salt!.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    
    _encryptionKey = EncryptionService.deriveKey(_passphrase!, _salt!);
    debugPrint('Server encryption key (first 16 bytes): ${_encryptionKey!.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
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
    router.get('/tags/<hash>', (Request request, String hash) => _tagHandlers.handleGetTagsForHash(request, hash));
    router.post('/tags/add', (Request request) => _tagHandlers.handleAddTag(request));
    router.post('/tags/remove', (Request request) => _tagHandlers.handleRemoveTag(request));
    router.get('/tags/all-hashes', (Request request) => _tagHandlers.handleGetAllTaggedHashes(request));

    return router;
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    await disableRelayMode();
  }
  
  /// Enable relay mode for internet access
  Future<String> enableRelayMode({String relayUrl = 'ws://127.0.0.1:8081'}) async {
    if (_relayMode) {
      debugPrint('Relay mode already enabled');
      return _relayClient!.roomId!;
    }
    
    try {
      _relayClient = RelayClient(relayUrl: relayUrl);
      final roomId = await _relayClient!.registerAsHost();
      _relayMode = true;
      
      debugPrint('Relay mode enabled with room ID: $roomId');
      
      debugPrint('Setting up relay message listener...');
      _relayClient!.messages.listen((message) {
        debugPrint('📩 Received relay message type: ${message['type']}');
        if (message['type'] == 'request') {
          debugPrint('🔥 Processing relay request...');
          _handleRelayRequest(message);
        } else {
          debugPrint('⚠️ Ignoring non-request message: ${message['type']}');
        }
      });
      
      debugPrint('✅ Relay message listener active');
      return roomId;
    } catch (e) {
      debugPrint('Failed to enable relay mode: $e');
      _relayClient = null;
      rethrow;
    }
  }
  
  /// Disable relay mode
  Future<void> disableRelayMode() async {
    if (_relayClient != null) {
      await _relayClient!.disconnect();
      _relayClient = null;
      _relayMode = false;
      debugPrint('Relay mode disabled');
    }
  }
  
  /// Handle incoming request from relay
  Future<void> _handleRelayRequest(Map<String, dynamic> message) async {
    final requestId = message['requestId'] as String;
    final data = message['data'] as String;
    
    try {
      final requestBytes = base64.decode(data);
      final requestText = utf8.decode(requestBytes);
      
      debugPrint('Received relay request: $requestId');
      debugPrint('Request: ${requestText.substring(0, min(100, requestText.length))}...');
      
      final lines = requestText.split('\r\n');
      if (lines.isEmpty) {
        debugPrint('Invalid HTTP request');
        return;
      }
      
      final requestLine = lines[0];
      final parts = requestLine.split(' ');
      if (parts.length < 2) {
        debugPrint('Invalid HTTP request line');
        return;
      }
      
      final method = parts[0];
      final uri = Uri.parse(parts[1]);
      
      // Route to appropriate handler
      Response response;
      if (uri.path == '/files') {
        final queryParams = uri.queryParameters;
        response = await _fileHandlers.handleGetFiles(Request(
          method,
          Uri.http('localhost', '/files', queryParams),
        ));
      } else if (uri.path == '/tags/all-hashes') {
        response = await _tagHandlers.handleGetAllTaggedHashes(Request(
          method,
          Uri.http('localhost', '/tags/all-hashes'),
        ));
      } else {
        response = Response.notFound('Not found');
      }
      
      final responseBody = await response.readAsString();
      final responseData = base64.encode(utf8.encode(responseBody));
      
      _relayClient!.sendResponse(requestId, responseData);
      debugPrint('Sent response for request $requestId');
      
    } catch (e) {
      debugPrint('Error handling relay request: $e');
    }
  }

  void updateRootDirectory(String newRootDirectory) {
    _rootDirectory = newRootDirectory;
    debugPrint('Updated server root directory to: $newRootDirectory');
  }
  
  Future<void> regeneratePassphrase() async {
    _passphrase = EncryptionService.generatePassphrase();
    debugPrint('Regenerated new server passphrase: $_passphrase');
    
    _salt = EncryptionService.deriveSaltFromPassphrase(_passphrase!);
    debugPrint('Server salt: ${_salt!.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    
    _encryptionKey = EncryptionService.deriveKey(_passphrase!, _salt!);
    debugPrint('Server encryption key (first 16 bytes): ${_encryptionKey!.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_passphrase', _passphrase!);
    debugPrint('Saved regenerated passphrase to storage');
  }
  
  // Getters for encryption
  String? get passphrase => _passphrase;
  Uint8List? get salt => _salt;
}
