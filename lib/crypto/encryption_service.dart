import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class EncryptionService {
  static const int _iterations = 100000;
  static const int _keyLength = 32; // 256 bits
  static const int _saltLength = 16;
  static const int _ivLength = 16;

  /// Generate a random passphrase
  static String generatePassphrase({int wordCount = 4}) {
    const words = [
      'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot',
      'golf', 'hotel', 'india', 'juliet', 'kilo', 'lima',
      'mike', 'november', 'oscar', 'papa', 'quebec', 'romeo',
      'sierra', 'tango', 'uniform', 'victor', 'whiskey', 'xray',
      'yankee', 'zulu', 'zero', 'one', 'two', 'three', 'four',
    ];
    
    final random = Random.secure();
    final selectedWords = List.generate(
      wordCount,
      (_) => words[random.nextInt(words.length)],
    );
    
    return selectedWords.join('-');
  }

  /// Generate a random salt
  static Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_saltLength, (_) => random.nextInt(256)),
    );
  }
  
  /// Derive salt from passphrase deterministically
  /// Both host and client can derive same salt from same passphrase
  static Uint8List deriveSaltFromPassphrase(String passphrase) {
    final bytes = utf8.encode(passphrase);
    final hash = sha256.convert(bytes);
    // Use first 16 bytes of hash as salt
    return Uint8List.fromList(hash.bytes.sublist(0, _saltLength));
  }

  /// Derive encryption key from passphrase using PB KDF2
  static Uint8List deriveKey(String passphrase, Uint8List salt) {
    final pbkdf2 = Pbkdf2(
      iterations: _iterations,
      bits: _keyLength * 8,
    );
    
    final key = pbkdf2.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt.toList(),
    );
    
    return Uint8List.fromList(key);
  }

  /// Encrypt data using AES-256-GCM
  static Uint8List encrypt(Uint8List data, Uint8List key) {
    // Generate random IV
    final random = Random.secure();
    final iv = enc.IV.fromLength(_ivLength);
    for (int i = 0; i < _ivLength; i++) {
      iv.bytes[i] = random.nextInt(256);
    }

    // Create encrypter
    final encKey = enc.Key(key);
    final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.gcm));

    // Encrypt
    final encrypted = encrypter.encryptBytes(data, iv: iv);

    // Combine IV + ciphertext + auth tag
    final result = BytesBuilder();
    result.add(iv.bytes);
    result.add(encrypted.bytes);
    
    return result.toBytes();
  }

  /// Decrypt data using AES-256-GCM
  static Uint8List? decrypt(Uint8List encryptedData, Uint8List key) {
    try {
      // Extract IV (first 16 bytes)
      final iv = enc.IV(encryptedData.sublist(0, _ivLength));
      
      // Extract ciphertext + auth tag (rest)
      final ciphertext = encryptedData.sublist(_ivLength);

      // Create encrypter
      final encKey = enc.Key(key);
      final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.gcm));

      // Decrypt
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted(ciphertext),
        iv: iv,
      );

      return Uint8List.fromList(decrypted);
    } catch (e) {
      // Decryption failed (wrong passphrase or corrupted data)
      return null;
    }
  }

  /// Encrypt string data
  static String encryptString(String data, Uint8List key) {
    final dataBytes = utf8.encode(data);
    final encrypted = encrypt(Uint8List.fromList(dataBytes), key);
    return base64.encode(encrypted);
  }

  /// Decrypt string data
  static String? decryptString(String encryptedData, Uint8List key) {
    try {
      final encryptedBytes = base64.decode(encryptedData);
      final decrypted = decrypt(encryptedBytes, key);
      if (decrypted == null) return null;
      return utf8.decode(decrypted);
    } catch (e) {
      return null;
    }
  }
}

/// Simple PBKDF2 implementation
class Pbkdf2 {
  final int iterations;
  final int bits;

  Pbkdf2({
    required this.iterations,
    required this.bits,
  });

  List<int> deriveKeyFromPassword({
    required String password,
    required List<int> nonce,
  }) {
    final passwordBytes = utf8.encode(password);
    final dkLen = (bits / 8).ceil();
    final hLen = 32; // SHA256 output length
    final l = (dkLen / hLen).ceil();
    
    final derivedKey = <int>[];
    
    for (int i = 1; i <= l; i++) {
      final block = _f(passwordBytes, nonce, i);
      derivedKey.addAll(block);
    }
    
    return derivedKey.sublist(0, dkLen);
  }

  List<int> _f(List<int> password, List<int> salt, int blockIndex) {
    final hmac = Hmac(sha256, password);
    
    // U1 = PRF(password, salt || blockIndex)
    final saltWithIndex = [...salt, ..._intToBytes(blockIndex)];
    var u = hmac.convert(saltWithIndex).bytes;
    var result = List<int>.from(u);
    
    // U2 through Uc
    for (int i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    
    return result;
  }

  List<int> _intToBytes(int value) {
    return [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];
  }
}
