import 'package:shelf/shelf.dart';
import '../../crypto/encryption_service.dart';
import 'dart:typed_data';

/// Helper to encrypt HTTP responses if encryption is enabled
class EncryptionHelper {
  /// Encrypts response body if encryption key is provided
  static Response encryptResponse(String jsonBody, Uint8List? encryptionKey) {
    if (encryptionKey == null) {
      // No encryption - return as-is
      return Response.ok(
        jsonBody,
        headers: {'content-type': 'application/json'},
      );
    }
    
    // Encrypt the response
    final encrypted = EncryptionService.encryptString(jsonBody, encryptionKey);
    return Response.ok(
      encrypted,
      headers: {
        'content-type': 'application/json',
        'x-encrypted': 'true',
      },
    );
  }
}
