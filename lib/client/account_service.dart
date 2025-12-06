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
  bool _isInitialized = false;
  String? _lastError;
  Timer? _autoCheckTimer;
  
  // Getters
  String? get savedUsername => _savedUsername;
  String? get savedPassphrase => _savedPassphrase;
  String get relayUrl => _relayUrl;
  List<String> get availableHosts => _availableHosts;
  bool get isChecking => _isChecking;
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  bool get hasAccount => _savedUsername != null && _savedPassphrase != null;
  bool get hostsAvailable => _availableHosts.isNotEmpty;
  
  /// Initialize - load saved settings and start auto-check
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadSettings();
    _isInitialized = true;
    
    if (hasAccount) {
      // Check immediately
      await checkForHosts();
      // Start periodic checks
      _startAutoCheck();
    }
  }
  
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedUsername = prefs.getString(_usernameKey);
      _savedPassphrase = prefs.getString(_passphraseKey);
      _relayUrl = prefs.getString(_relayUrlKey) ?? _defaultRelayUrl;
      notifyListeners();
      debugPrint('AccountService: Loaded account: ${_savedUsername ?? "none"}, relay: $_relayUrl');
    } catch (e) {
      debugPrint('AccountService: Error loading settings: $e');
      _lastError = 'Failed to load settings: $e';
    }
  }
  
  /// Save account credentials
  Future<void> saveAccount(String username, String passphrase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usernameKey, username);
      await prefs.setString(_passphraseKey, passphrase);
      _savedUsername = username;
      _savedPassphrase = passphrase;
      _lastError = null;
      notifyListeners();
      
      // Start checking for hosts
      await checkForHosts();
      _startAutoCheck();
      
      debugPrint('AccountService: Account saved: $username');
    } catch (e) {
      debugPrint('AccountService: Error saving account: $e');
      _lastError = 'Failed to save account: $e';
      notifyListeners();
    }
  }
  
  /// Clear saved account
  Future<void> clearAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usernameKey);
      await prefs.remove(_passphraseKey);
      _savedUsername = null;
      _savedPassphrase = null;
      _availableHosts = [];
      _lastError = null;
      _stopAutoCheck();
      notifyListeners();
      debugPrint('AccountService: Account cleared');
    } catch (e) {
      debugPrint('AccountService: Error clearing account: $e');
      _lastError = 'Failed to clear account: $e';
      notifyListeners();
    }
  }
  
  /// Update relay URL
  Future<void> setRelayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_relayUrlKey, url);
    _relayUrl = url;
    notifyListeners();
    
    // Re-check with new URL
    if (hasAccount) {
      await checkForHosts();
    }
  }
  
  /// Check for available hosts via relay server
  Future<void> checkForHosts() async {
    if (_savedUsername == null) {
      debugPrint('AccountService: No username saved, skipping host check');
      return;
    }
    
    _isChecking = true;
    _lastError = null;
    notifyListeners();
    
    try {
      debugPrint('AccountService: Checking hosts for "$_savedUsername" at $_relayUrl');
      
      final connection = RelayConnection(_relayUrl);
      final hosts = await connection.checkHostsForUsername(_savedUsername!);
      
      _availableHosts = hosts;
      debugPrint('AccountService: Found ${hosts.length} hosts: $hosts');
      
    } catch (e) {
      debugPrint('AccountService: Error checking hosts: $e');
      _lastError = 'Connection error: $e';
      _availableHosts = [];
    }
    
    _isChecking = false;
    notifyListeners();
  }
  
  void _startAutoCheck() {
    _stopAutoCheck();
    // Check every 15 seconds for better responsiveness
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkForHosts();
    });
    debugPrint('AccountService: Started auto-check timer (15s interval)');
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
