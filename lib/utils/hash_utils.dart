import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Utilities for computing SHA-256 file hashes
class HashUtils {
  /// Compute SHA-256 hash for a file at the given path
  /// Reads file in chunks for memory efficiency
  static Future<String> computeFileHash(String path) async {
    final file = File(path);
    
    if (!await file.exists()) {
      throw Exception('File not found: $path');
    }
    
    // Read file and compute hash
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
  
  /// Compute SHA-256 hash for a byte stream
  /// Useful for remote files being downloaded
  static Future<String> computeStreamHash(Stream<List<int>> stream) async {
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }
  
  /// Compute SHA-256 hash for in-memory bytes
  static String computeBytesHash(Uint8List bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
