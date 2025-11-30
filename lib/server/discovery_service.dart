import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

class DiscoveryService {
  nsd.Registration? _registration;

  Future<void> startAdvertising(int port) async {
    final hostname = Platform.localHostname;
    
    _registration = await nsd.register(
      nsd.Service(
        name: hostname.isNotEmpty ? hostname : 'SpacedriveHost',
        type: '_http._tcp',
        port: port,
      ),
    );
    debugPrint('Discovery service started: $hostname');
  }

  Future<void> stopAdvertising() async {
    if (_registration != null) {
      await nsd.unregister(_registration!);
      _registration = null;
    }
  }
}
