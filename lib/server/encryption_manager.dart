import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/encryption_service.dart';

/// Manages encryption passphrase and keys for the server
class EncryptionManager {
  String? _passphrase;
  Uint8List? _salt;
  Uint8List? _encryptionKey;
  
  String? get passphrase => _passphrase;
  Uint8List? get salt => _salt;
  Uint8List? get encryptionKey => _encryptionKey;
  
  /// Initialize encryption from stored passphrase or generate new one
  Future<void> initialize() async {
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
  
  /// Regenerate passphrase and encryption key
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
}
