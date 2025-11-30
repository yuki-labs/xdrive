import 'dart:convert';

enum FileType { file, directory }

class FileItem {
  final String path;
  final String name;
  final FileType type;
  final int size;
  final List<String> tags;
  final String? sha256;

  FileItem({
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    this.tags = const [],
    this.sha256,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      path: json['path'],
      name: json['name'],
      type: json['type'] == 'directory' ? FileType.directory : FileType.file,
      size: json['size'],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      sha256: json['sha256'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'type': type == FileType.directory ? 'directory' : 'file',
      'size': size,
      'tags': tags,
      'sha256': sha256,
    };
  }
  
  // Helper method to create a copy with updated tags
  FileItem copyWith({
    String? path,
    String? name,
    FileType? type,
    int? size,
    List<String>? tags,
    String? sha256,
  }) {
    return FileItem(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      size: size ?? this.size,
      tags: tags ?? this.tags,
      sha256: sha256 ?? this.sha256,
    );
  }
}
