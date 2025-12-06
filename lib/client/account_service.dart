import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../relay/relay_connection.dart';

/// Manages saved account settings and auto-discovery of hosts
class AccountService with ChangeNotifier {
  static const String _usernameKey = 'saved_username';
  static const String _passphraseKey = 'saved_passphrase';
  static const String _relayUrlKey = 'relay_url';
  static const String _defaultRelayUrl = 'wss://xdrive-production.up.railway.app';
  
  String? _savedUsername;
  String? _savedPassphrase;
  String _relayUrl = _defaultRelayUrl;
  List<String> _availableHosts = [];
  bool _isChecking = false;
  Timer? _autoCheckTimer;
  
  // Getters
  String? get savedUsername => _savedUsername;
  String? get savedPassphrase => _savedPassphrase;
  String get relayUrl => _relayUrl;
  List<String> get availableHosts => _availableHosts;
  bool get isChecking => _isChecking;
  bool get hasAccount => _savedUsername != null && _savedPassphrase != null;
  bool get hostsAvailable => _availableHosts.isNotEmpty;
  
  /// Initialize - load saved settings and start auto-check
  Future<void> initialize() async {
    await _loadSettings();
    if (hasAccount) {
      await checkForHosts();
      _startAutoCheck();
    }
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _savedUsername = prefs.getString(_usernameKey);
    _savedPassphrase = prefs.getString(_passphraseKey);
    _relayUrl = prefs.getString(_relayUrlKey) ?? _defaultRelayUrl;
    notifyListeners();
    debugPrint('Loaded account: ${_savedUsername ?? "none"}');
  }
  
  /// Save account credentials
  Future<void> saveAccount(String username, String passphrase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_passphraseKey, passphrase);
    _savedUsername = username;
    _savedPassphrase = passphrase;
    notifyListeners();
    
    // Start checking for hosts
    await checkForHosts();
    _startAutoCheck();
    
    debugPrint('Account saved: $username');
  }
  
  /// Clear saved account
  Future<void> clearAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_passphraseKey);
    _savedUsername = null;
    _savedPassphrase = null;
    _availableHosts = [];
    _stopAutoCheck();
    notifyListeners();
    debugPrint('Account cleared');
  }
  
  /// Update relay URL
  Future<void> setRelayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_relayUrlKey, url);
    _relayUrl = url;
    notifyListeners();
  }
  
  /// Check for available hosts
  Future<void> checkForHosts() async {
    if (_savedUsername == null) return;
    
    _isChecking = true;
    notifyListeners();
    
    try {
      final connection = RelayConnection(_relayUrl);
      _availableHosts = await connection.checkHostsForUsername(_savedUsername!);
      debugPrint('Hosts found for $_savedUsername: $_availableHosts');
    } catch (e) {
      debugPrint('Error checking hosts: $e');
      _availableHosts = [];
    }
    
    _isChecking = false;
    notifyListeners();
  }
  
  void _startAutoCheck() {
    _stopAutoCheck();
    // Check every 30 seconds
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkForHosts();
    });
  }
  
  void _stopAutoCheck() {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = null;
  }
  
  @override
  void dispose() {
    _stopAutoCheck();
    super.dispose();
  }
}
