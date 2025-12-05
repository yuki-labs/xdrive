import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

/// Manages WebSocket connection to relay server for tunneling HTTP requests
class RelayConnection {
  WebSocketChannel? _channel;
  String? _roomId;
  String? _username;
  String? _selectedHost;
  List<String> _availableHosts = [];
  final Map<String, Completer<String>> _pendingRequests = {};
  final String _relayUrl;
  
  // Callbacks for UI updates
  Function(List<String>)? onHostsAvailable;
  Function(String)? onHostSelected;
  Function(String)? onError;
  Function()? onHostDisconnected;
  
  RelayConnection(this._relayUrl);
  
  String? get roomId => _roomId;
  String? get username => _username;
  String? get selectedHost => _selectedHost;
  List<String> get availableHosts => _availableHosts;
  bool get isConnected => _channel != null && _selectedHost != null;
  bool get isWaitingForHost => _channel != null && _selectedHost == null;
  
  /// Check if hosts are available for a username (without fully connecting)
  Future<List<String>> checkHostsForUsername(String username) async {
    try {
      debugPrint('Checking hosts for username: $username');
      
      // Create temporary connection
      final channel = WebSocketChannel.connect(Uri.parse(_relayUrl));
      final completer = Completer<List<String>>();
      
      // Send check request
      channel.sink.add(jsonEncode({
        'type': 'check-username',
        'username': username,
      }));
      
      // Listen for response
      final subscription = channel.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['type'] == 'hosts-check-result') {
          final hosts = List<String>.from(data['hosts'] ?? []);
          debugPrint('Hosts found for $username: $hosts');
          if (!completer.isCompleted) {
            completer.complete(hosts);
          }
        } else if (data['type'] == 'error') {
          if (!completer.isCompleted) {
            completer.complete([]); // No hosts found
          }
        }
      });
      
      // Wait with timeout
      final hosts = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => <String>[],
      );
      
      // Clean up
      await subscription.cancel();
      await channel.sink.close();
      
      return hosts;
    } catch (e) {
      debugPrint('Error checking hosts: $e');
      return [];
    }
  }
  
  /// Connect and join a room by room ID (legacy)
  Future<void> joinRoom(String roomId) async {
    try {
      debugPrint('Connecting to relay server: $_relayUrl');
      _channel = WebSocketChannel.connect(Uri.parse(_relayUrl));
      _roomId = roomId;
      
      // Send join message
      _channel!.sink.add(jsonEncode({
        'type': 'join',
        'roomId': roomId,
      }));
      
      debugPrint('Sent join message for room: $roomId');
      
      _setupMessageListener();
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      debugPrint('Failed to join room: $e');
      rethrow;
    }
  }
  
  /// Connect and join by username (new method)
  Future<void> joinByUsername(String username) async {
    try {
      debugPrint('Connecting to relay server: $_relayUrl');
      _channel = WebSocketChannel.connect(Uri.parse(_relayUrl));
      _username = username;
      _roomId = username.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');
      
      // Send join-username message
      _channel!.sink.add(jsonEncode({
        'type': 'join-username',
        'username': username,
      }));
      
      debugPrint('Sent join-username message for: $username');
      
      _setupMessageListener();
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      debugPrint('Failed to join by username: $e');
      rethrow;
    }
  }
  
  /// Select which host device to connect to
  Future<void> selectHost(String deviceName) async {
    if (_channel == null) {
      throw Exception('Not connected to relay');
    }
    
    _channel!.sink.add(jsonEncode({
      'type': 'select-host',
      'deviceName': deviceName,
    }));
    
    debugPrint('Selecting host: $deviceName');
  }
  
  void _setupMessageListener() {
    _channel!.stream.listen(
      (message) {
        debugPrint('Received message from relay: $message');
        final data = jsonDecode(message);
        
        switch (data['type']) {
          case 'joined':
            debugPrint('Joined room: ${data['roomId']}');
            break;
            
          case 'hosts-available':
            // Client received list of available hosts
            _availableHosts = List<String>.from(data['hosts'] ?? []);
            debugPrint('Available hosts: $_availableHosts');
            onHostsAvailable?.call(_availableHosts);
            
            // Auto-select if only one host
            if (_availableHosts.length == 1) {
              selectHost(_availableHosts.first);
            }
            break;
            
          case 'hosts-updated':
            // Host list changed (host connected/disconnected)
            _availableHosts = List<String>.from(data['hosts'] ?? []);
            debugPrint('Hosts updated: $_availableHosts');
            onHostsAvailable?.call(_availableHosts);
            
            // If our selected host disconnected, notify
            if (_selectedHost != null && !_availableHosts.contains(_selectedHost)) {
              _selectedHost = null;
              onHostDisconnected?.call();
            }
            break;
            
          case 'host-selected':
            _selectedHost = data['deviceName'];
            debugPrint('Host selected: $_selectedHost');
            onHostSelected?.call(_selectedHost!);
            break;
            
          case 'response':
            final requestId = data['requestId'];
            if (_pendingRequests.containsKey(requestId)) {
              _pendingRequests[requestId]!.complete(data['data']);
              _pendingRequests.remove(requestId);
            }
            break;
            
          case 'error':
            final errorMsg = data['message'] ?? 'Unknown error';
            debugPrint('Relay error: $errorMsg');
            onError?.call(errorMsg);
            
            // Complete pending request if has requestId
            if (data['requestId'] != null) {
              final requestId = data['requestId'];
              if (_pendingRequests.containsKey(requestId)) {
                _pendingRequests[requestId]!.completeError(Exception(errorMsg));
                _pendingRequests.remove(requestId);
              }
            }
            break;
        }
      },
      onError: (error) {
        debugPrint('Relay WebSocket error: $error');
        for (var completer in _pendingRequests.values) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
        _pendingRequests.clear();
      },
      onDone: () {
        debugPrint('Relay WebSocket closed');
        _channel = null;
        _roomId = null;
        _username = null;
        _selectedHost = null;
        _availableHosts = [];
        for (var completer in _pendingRequests.values) {
          if (!completer.isCompleted) {
            completer.completeError(Exception('Connection closed'));
          }
        }
        _pendingRequests.clear();
      },
    );
  }
  
  /// Send request through relay and wait for response
  Future<String> sendRequest(String data) async {
    if (_channel == null) {
      throw Exception('Not connected to relay. Please reconnect.');
    }
    
    final requestId = const Uuid().v4();
    final completer = Completer<String>();
    _pendingRequests[requestId] = completer;
    
    final message = jsonEncode({
      'type': 'request',
      'requestId': requestId,
      'data': data,
    });
    
    try {
      _channel!.sink.add(message);
      debugPrint('Sent request $requestId');
    } catch (e) {
      _pendingRequests.remove(requestId);
      debugPrint('Error sending request: $e');
      throw Exception('Failed to send request: $e');
    }
    
    // Set timeout - longer for large files (videos)
    Future.delayed(const Duration(minutes: 5), () {
      if (_pendingRequests.containsKey(requestId)) {
        if (!_pendingRequests[requestId]!.isCompleted) {
          _pendingRequests[requestId]!.completeError(
            TimeoutException('Request timed out', const Duration(minutes: 5))
          );
        }
        _pendingRequests.remove(requestId);
      }
    });
    
    return completer.future;
  }
  
  /// Disconnect from relay server
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _roomId = null;
    _username = null;
    _selectedHost = null;
    _availableHosts = [];
  }
}
