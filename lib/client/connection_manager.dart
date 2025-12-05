import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/encryption_service.dart';
import '../relay/relay_connection.dart';

/// Manages network discovery and connection to remote services
class ConnectionManager with ChangeNotifier {
  List<nsd.Service> _discoveredServices = [];
  List<nsd.Service> get discoveredServices => _discoveredServices;

  nsd.Service? _connectedService;
  nsd.Service? get connectedService => _connectedService;

  nsd.Discovery? _discovery;
  
  // Encryption
  Uint8List? _encryptionKey;
  Uint8List? get encryptionKey => _encryptionKey;
  
  // Track decryption failures
  bool _decryptionFailed = false;
  bool get decryptionFailed => _decryptionFailed;
  
  // Callback for when decryption fails
  Function()? onDecryptionFailed;
  
  // Relay connection
  RelayConnection? _relayConnection;
  RelayConnection? get relayConnection => _relayConnection;
  
  bool _usingRelay = false;
  bool get usingRelay => _usingRelay;
  
  // Username-based connection info
  String? _relayUsername;
  String? get relayUsername => _relayUsername;
  
  List<String> _availableHosts = [];
  List<String> get availableHosts => _availableHosts;
  
  String? _selectedHost;
  String? get selectedHost => _selectedHost;

  Future<void> startDiscovery() async {
    _discovery = await nsd.startDiscovery('_http._tcp');
    _discovery!.addServiceListener((service, status) {
      if (status == nsd.ServiceStatus.found) {
        debugPrint('Service discovered: name="${service.name}", host=${service.host}, port=${service.port}');
        
        final existingIndex = _discoveredServices.indexWhere((s) =>
            s.host == service.host && s.port == service.port);
        
        if (existingIndex == -1) {
          _discoveredServices.add(service);
          notifyListeners();
        } else {
          final existing = _discoveredServices[existingIndex];
          final existingName = existing.name ?? '';
          final newName = service.name ?? '';
          
          final existingHasNumber = existingName.contains(RegExp(r'\(\d+\)'));
          final newHasNumber = newName.contains(RegExp(r'\(\d+\)'));
          
          if (!newHasNumber && existingHasNumber) {
            debugPrint('Updating service name from "$existingName" to "$newName"');
            _discoveredServices[existingIndex] = service;
            notifyListeners();
          }
        }
      } else {
        debugPrint('Service lost: name="${service.name}", host=${service.host}');
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
    _relayConnection?.disconnect();
    _relayConnection = null;
    _usingRelay = false;
    _relayUsername = null;
    _availableHosts = [];
    _selectedHost = null;
    notifyListeners();
  }
  
  /// Connect via relay using room ID (legacy)
  Future<void> connectViaRelay(String roomId, String passphrase, {String relayUrl = 'ws://192.168.1.3:8081'}) async {
    try {
      debugPrint('Connecting via relay to room: $roomId');
      
      final salt = EncryptionService.deriveSaltFromPassphrase(passphrase);
      _encryptionKey = EncryptionService.deriveKey(passphrase, salt);
      debugPrint('Encryption key derived for relay connection');
      
      _relayConnection = RelayConnection(relayUrl);
      await _relayConnection!.joinRoom(roomId);
      
      _usingRelay = true;
      
      _connectedService = nsd.Service(
        name: 'Internet Connection',
        type: '_http._tcp',
        host: 'relay',
        port: 0,
      );
      
      debugPrint('Connected via relay');
      notifyListeners();
      
    } catch (e) {
      debugPrint('Failed to connect via relay: $e');
      _relayConnection = null;
      _usingRelay = false;
      rethrow;
    }
  }
  
  /// Connect via relay using username (new method)
  /// Returns list of available hosts if multiple, or auto-connects if only one
  Future<List<String>> connectViaUsername(String username, String passphrase, {String relayUrl = 'ws://192.168.1.3:8081'}) async {
    try {
      debugPrint('Connecting via relay to username: $username');
      
      final salt = EncryptionService.deriveSaltFromPassphrase(passphrase);
      _encryptionKey = EncryptionService.deriveKey(passphrase, salt);
      debugPrint('Encryption key derived for relay connection');
      
      _relayConnection = RelayConnection(relayUrl);
      _relayUsername = username;
      
      // Set up callbacks before joining
      final hostCompleter = Completer<List<String>>();
      
      _relayConnection!.onHostsAvailable = (hosts) {
        _availableHosts = hosts;
        notifyListeners();
        if (!hostCompleter.isCompleted) {
          hostCompleter.complete(hosts);
        }
      };
      
      _relayConnection!.onHostSelected = (deviceName) {
        _selectedHost = deviceName;
        _usingRelay = true;
        
        _connectedService = nsd.Service(
          name: 'Internet: $deviceName',
          type: '_http._tcp',
          host: 'relay',
          port: 0,
        );
        
        debugPrint('Connected to host: $deviceName');
        notifyListeners();
      };
      
      _relayConnection!.onError = (error) {
        debugPrint('Relay error: $error');
        if (!hostCompleter.isCompleted) {
          hostCompleter.completeError(Exception(error));
        }
      };
      
      await _relayConnection!.joinByUsername(username);
      
      // Wait for hosts list (with timeout)
      final hosts = await hostCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Timeout waiting for hosts'),
      );
      
      return hosts;
      
    } catch (e) {
      debugPrint('Failed to connect via username: $e');
      _relayConnection = null;
      _usingRelay = false;
      _relayUsername = null;
      rethrow;
    }
  }
  
  /// Select a specific host device to connect to
  Future<void> selectHost(String deviceName) async {
    if (_relayConnection == null) {
      throw Exception('Not connected to relay');
    }
    
    await _relayConnection!.selectHost(deviceName);
  }
  
  Future<String?> getSavedPassphrase(nsd.Service service) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'passphrase_${service.host}_${service.port}';
    return prefs.getString(key);
  }
  
  Future<void> savePassphrase(nsd.Service service, String passphrase) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'passphrase_${service.host}_${service.port}';
    await prefs.setString(key, passphrase);
    debugPrint('Saved passphrase for ${service.host}:${service.port}');
  }

  void connectToService(nsd.Service service, {String? passphrase}) {
    _connectedService = service;
    
    debugPrint('connectToService called with passphrase: ${passphrase != null ? "provided (${passphrase.length} chars)" : "null"}');
    
    if (passphrase != null) {
      debugPrint('Deriving salt from passphrase...');
      final salt = EncryptionService.deriveSaltFromPassphrase(passphrase);
      debugPrint('Deriving encryption key...');
      _encryptionKey = EncryptionService.deriveKey(passphrase, salt);
      debugPrint('Encryption key derived: ${_encryptionKey != null ? "${_encryptionKey!.length} bytes" : "null"}');
      
      savePassphrase(service, passphrase);
    } else {
      debugPrint('No passphrase provided - encryption disabled');
      _encryptionKey = null;
    }
    
    notifyListeners();
  }
  
  void setDecryptionFailed(bool failed) {
    _decryptionFailed = failed;
    if (failed && onDecryptionFailed != null) {
      onDecryptionFailed!();
    }
    notifyListeners();
  }
}
