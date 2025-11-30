import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
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
  }
  
  void setDecryptionFailed(bool failed) {
    _decryptionFailed = failed;
    if (failed && onDecryptionFailed != null) {
      onDecryptionFailed!();
    }
    notifyListeners();
  }
}
