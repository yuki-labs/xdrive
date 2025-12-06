import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Manages saved account settings and real-time host discovery
class AccountService with ChangeNotifier {
  static const String _usernameKey = 'saved_username';
  static const String _passphraseKey = 'saved_passphrase';
  static const String _relayUrlKey = 'relay_url';
  static const String _defaultRelayUrl = 'wss://xdrive-production.up.railway.app';
  
  String? _savedUsername;
  String? _savedPassphrase;
  String _relayUrl = _defaultRelayUrl;
  List<String> _availableHosts = [];
  bool _isConnected = false;
  bool _isInitialized = false;
  String? _lastError;
  
  WebSocketChannel? _watchChannel;
  StreamSubscription? _watchSubscription;
  Timer? _reconnectTimer;
  
  // Getters
  String? get savedUsername => _savedUsername;
  String? get savedPassphrase => _savedPassphrase;
  String get relayUrl => _relayUrl;
  List<String> get availableHosts => _availableHosts;
  bool get isConnected => _isConnected;
  bool get isChecking => !_isConnected && _savedUsername != null; // Show as "checking" until connected
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  bool get hasAccount => _savedUsername != null && _savedPassphrase != null;
  bool get hostsAvailable => _availableHosts.isNotEmpty;
  
  /// Initialize - load saved settings and start watching
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadSettings();
    _isInitialized = true;
    
    if (hasAccount) {
      _startWatching();
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
      
      // Start watching for hosts
      _startWatching();
      
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
      _stopWatching();
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
    
    // Reconnect with new URL
    if (hasAccount) {
      _stopWatching();
      _startWatching();
    }
  }
  
  /// Start watching for host updates via persistent WebSocket
  void _startWatching() {
    if (_savedUsername == null) return;
    
    _stopWatching(); // Clean up any existing connection
    
    debugPrint('AccountService: Starting watcher for "$_savedUsername" at $_relayUrl');
    
    try {
      _watchChannel = WebSocketChannel.connect(Uri.parse(_relayUrl));
      
      // Send watch request
      _watchChannel!.sink.add(jsonEncode({
        'type': 'watch-username',
        'username': _savedUsername,
      }));
      
      // Listen for updates
      _watchSubscription = _watchChannel!.stream.listen(
        (message) {
          _handleWatchMessage(message);
        },
        onError: (error) {
          debugPrint('AccountService: WebSocket error: $error');
          _lastError = 'Connection error';
          _isConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('AccountService: WebSocket closed');
          _isConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
      );
      
      _isConnected = true;
      _lastError = null;
      notifyListeners();
      
    } catch (e) {
      debugPrint('AccountService: Failed to connect: $e');
      _lastError = 'Connection failed: $e';
      _isConnected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }
  
  void _handleWatchMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      debugPrint('AccountService: Received ${data['type']}');
      
      if (data['type'] == 'hosts-updated') {
        _availableHosts = List<String>.from(data['hosts'] ?? []);
        _lastError = null;
        debugPrint('AccountService: Hosts updated: $_availableHosts');
        notifyListeners();
      } else if (data['type'] == 'error') {
        _lastError = data['message'] ?? 'Unknown error';
        notifyListeners();
      } else if (data['type'] == 'pong') {
        // Heartbeat response, ignore
      }
    } catch (e) {
      debugPrint('AccountService: Error parsing message: $e');
    }
  }
  
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (hasAccount && !_isConnected) {
        debugPrint('AccountService: Attempting reconnect...');
        _startWatching();
      }
    });
  }
  
  void _stopWatching() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _watchSubscription?.cancel();
    _watchSubscription = null;
    _watchChannel?.sink.close();
    _watchChannel = null;
    _isConnected = false;
  }
  
  /// Manual refresh - reconnect to get latest hosts
  Future<void> checkForHosts() async {
    _stopWatching();
    _startWatching();
  }
  
  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }
}
