import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

/// SQLite database for storing file hashes and tags
/// Uses singleton pattern to ensure all providers share the same database
class TagDatabase {
  static final TagDatabase _instance = TagDatabase._internal();
  static Database? _database;

  factory TagDatabase() {
    return _instance;
  }

  TagDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tags.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // File hash library (path → hash mapping)
    await db.execute('''
      CREATE TABLE file_hashes (
        path TEXT PRIMARY KEY,
        sha256 TEXT NOT NULL,
        last_modified INTEGER,
        size INTEGER
      )
    ''');

    // Tag storage (hash → tags)
    await db.execute('''
      CREATE TABLE file_tags (
        sha256 TEXT,
        tag TEXT,
        created_at INTEGER,
        PRIMARY KEY (sha256, tag)
      )
    ''');

    // Index for faster tag searches
    await db.execute('''
      CREATE INDEX idx_tag ON file_tags(tag)
    ''');
  }

  // Hash library operations
  Future<void> updateFileHash(String path, String sha256, int lastModified, int size) async {
    final db = await database;
    await db.insert(
      'file_hashes',
      {
        'path': path,
        'sha256': sha256,
        'last_modified': lastModified,
        'size': size,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('Updated hash for $path: $sha256');
  }

  Future<String?> getHashForPath(String path) async {
    final db = await database;
    final result = await db.query(
      'file_hashes',
      columns: ['sha256'],
      where: 'path = ?',
      whereArgs: [path],
    );
    
    if (result.isEmpty) return null;
    return result.first['sha256'] as String;
  }

  Future<List<String>> getPathsForHash(String sha256) async {
    final db = await database;
    final result = await db.query(
      'file_hashes',
      columns: ['path'],
      where: 'sha256 = ?',
      whereArgs: [sha256],
    );
    
    return result.map((row) => row['path'] as String).toList();
  }

  Future<void> removeFileHash(String path) async {
    final db = await database;
    await db.delete(
      'file_hashes',
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  // Tag operations
  Future<void> addTag(String sha256, String tag) async {
    final db = await database;
    try {
      await db.insert(
        'file_tags',
        {
          'sha256': sha256,
          'tag': tag,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      debugPrint('Added tag "$tag" to $sha256');
    } catch (e) {
      debugPrint('Error adding tag: $e');
    }
  }

  Future<void> removeTag(String sha256, String tag) async {
    final db = await database;
    await db.delete(
      'file_tags',
      where: 'sha256 = ? AND tag = ?',
      whereArgs: [sha256, tag],
    );
    debugPrint('Removed tag "$tag" from $sha256');
  }

  Future<List<String>> getTags(String sha256) async {
    final db = await database;
    final result = await db.query(
      'file_tags',
      columns: ['tag'],
      where: 'sha256 = ?',
      whereArgs: [sha256],
      orderBy: 'tag ASC',
    );
    
    return result.map((row) => row['tag'] as String).toList();
  }

  Future<List<String>> getAllTags() async {
    final db = await database;
    final result = await db.query(
      'file_tags',
      columns: ['DISTINCT tag'],
      orderBy: 'tag ASC',
    );
    
    return result.map((row) => row['tag'] as String).toList();
  }

  Future<List<String>> searchByTag(String tag) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT fh.path
      FROM file_hashes fh
      INNER JOIN file_tags ft ON fh.sha256 = ft.sha256
      WHERE ft.tag = ?
      ORDER BY fh.path ASC
    ''', [tag]);
    
    return result.map((row) => row['path'] as String).toList();
  }

  Future<Map<String, List<String>>> searchByTags(List<String> tags) async {
    if (tags.isEmpty) return {};
    
    final db = await database;
    final placeholders = tags.map((_) => '?').join(',');
    final result = await db.rawQuery('''
      SELECT fh.path, ft.tag
      FROM file_hashes fh
      INNER JOIN file_tags ft ON fh.sha256 = ft.sha256
      WHERE ft.tag IN ($placeholders)
      ORDER BY fh.path ASC
    ''', tags);
    
    final Map<String, List<String>> pathTags = {};
    for (final row in result) {
      final path = row['path'] as String;
      final tag = row['tag'] as String;
      pathTags.putIfAbsent(path, () => []).add(tag);
    }
    
    return pathTags;
  }

  // Cleanup operations
  Future<void> cleanupNonexistentPaths(List<String> existingPaths) async {
    final db = await database;
    final allPaths = await db.query('file_hashes', columns: ['path']);
    
    for (final row in allPaths) {
      final path = row['path'] as String;
      if (!existingPaths.contains(path)) {
        await removeFileHash(path);
      }
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
