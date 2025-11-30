import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import '../../storage/tag_database.dart';
import '../utils/encryption_helper.dart';

/// Handles tag-related HTTP requests
class TagHandlers {
  final TagDatabase tagDb;
  final Uint8List? encryptionKey;

  TagHandlers({required this.tagDb, this.encryptionKey});

  /// Handle GET /tags/{hash}
  Future<Response> handleGetTagsForHash(Request request, String hash) async {
    try {
      final tags = await tagDb.getTags(hash);
      final jsonBody = jsonEncode({'hash': hash, 'tags': tags});
      return EncryptionHelper.encryptResponse(jsonBody, encryptionKey);
    } catch (e) {
      print('Error getting tags for hash: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Handle POST /tags/add
  Future<Response> handleAddTag(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final hash = data['hash'] as String?;
      final tag = data['tag'] as String?;

      if (hash == null || tag == null) {
        return Response.badRequest(body: 'Missing hash or tag');
      }

      await tagDb.addTag(hash, tag);
      print('Added tag "$tag" to hash $hash on server');
      
      final jsonBody = jsonEncode({'success': true});
      return EncryptionHelper.encryptResponse(jsonBody, encryptionKey);
    } catch (e) {
      print('Error adding tag: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Handle POST /tags/remove
  Future<Response> handleRemoveTag(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final hash = data['hash'] as String?;
      final tag = data['tag'] as String?;

      if (hash == null || tag == null) {
        return Response.badRequest(body: 'Missing hash or tag');
      }

      await tagDb.removeTag(hash, tag);
      print('Removed tag "$tag" from hash $hash on server');
      
      final jsonBody = jsonEncode({'success': true});
      return EncryptionHelper.encryptResponse(jsonBody, encryptionKey);
    } catch (e) {
      print('Error removing tag: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  /// Handle GET /tags/all-hashes
  Future<Response> handleGetAllTaggedHashes(Request request) async {
    try {
      // Get all unique tags
      final allTags = await tagDb.getAllTags();
      
      // Build hash -> tags map
      final Map<String, List<String>> hashTagsMap = {};
      
      for (final tag in allTags) {
        // Get all paths for this tag
        final paths = await tagDb.searchByTag(tag);
        
        // For each path, get its hash and add the tag
        for (final path in paths) {
          final hash = await tagDb.getHashForPath(path);
          if (hash != null) {
            hashTagsMap.putIfAbsent(hash, () => []).add(tag);
          }
        }
      }
      
      final jsonBody = jsonEncode({'hashTags': hashTagsMap});
      return EncryptionHelper.encryptResponse(jsonBody, encryptionKey);
    } catch (e) {
      print('Error getting all tagged hashes: $e');
      return Response.internalServerError(body: 'Error: $e');
    }
  }
}
