import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/file_item.dart';
import '../../client/remote_file_provider.dart';
import '../video_player_view.dart';
import '../image_viewer_view.dart';
import '../views/audio_player_view.dart';
import '../dialogs/file_operation_dialogs.dart';
import '../dialogs/tag_dialog.dart';

/// Mixin for handling file operations in browser views
mixin FileOperationsHandler<T extends StatefulWidget> on State<T> {
  
  // Abstract methods - must be implemented by the using class
  String get currentPath;
  void refreshFiles();
  
  Future<void> handleManageTags(BuildContext context, FileItem file, RemoteFileProvider provider) async {
    // Get scaffold messenger before any async operations to avoid stale context
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      // Don't allow tagging directories
      if (file.type == FileType.directory) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Cannot tag directories - only files can be tagged'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final availableTags = await provider.getAllTags();
      
      if (!mounted) return;
      
      // Show dialog immediately - no hash computation needed!
      final newTags = await showDialog<List<String>>(
        context: context,
        builder: (context) => TagDialog(
          fileName: file.name,
          currentTags: file.tags,
          availableTags: availableTags,
        ),
      );
      
      debugPrint('===== TAG DIALOG CLOSED =====');
      debugPrint('File: ${file.name}');
      debugPrint('Original tags: ${file.tags}');
      debugPrint('New tags from dialog: $newTags');
      debugPrint('=============================');
      
      if (newTags != null) {
        if (!mounted) return;
        
        debugPrint('Saving tags for ${file.name}: $newTags');
        
        // Save tags immediately - updateFileTags will handle hash internally
        final result = await provider.updateFileTags(file.path, newTags, currentPath);
        
        debugPrint('updateFileTags result: $result');
        
        if (!mounted) return;
        
        if (result['success']) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Tags updated successfully')),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Unknown error occurred'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        debugPrint('Dialog was cancelled (newTags is null)');
      }
    } catch (e) {
      if (!mounted) return;
      // Use pre-captured scaffold messenger to avoid context issues
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error managing tags: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  Future<void> handleViewHash(BuildContext context, FileItem file, RemoteFileProvider provider) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      // Check if file has hash already
      final existingHash = file.sha256;
      
      if (existingHash != null && existingHash.isNotEmpty) {
        // Hash exists - show it in a dialog
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('File Hash'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('File: ${file.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('SHA-256:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                SelectableText(
                  existingHash,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else {
        // No hash yet - show progress dialog and compute it
        if (!mounted) return;
        
        final isComputing = ValueNotifier<bool>(true);
        final computedHash = ValueNotifier<String?>(null);
        final error = ValueNotifier<String?>(null);
        
        // Show progress dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ValueListenableBuilder<bool>(
            valueListenable: isComputing,
            builder: (context, computing, child) {
              return AlertDialog(
                title: const Text('File Hash'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('File: ${file.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    if (computing) ...[
                      const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Expanded(child: Text('Computing hash...')),
                        ],
                      ),
                    ] else if (error.value != null) ...[
                      Text(
                        'Error: ${error.value}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ] else if (computedHash.value != null) ...[
                      const Text('SHA-256:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      SelectableText(
                        computedHash.value!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          ),
        );
        
        // Start hash computation
        provider.ensureFileHasHash(file.path).then((result) {
          if (result['success']) {
            computedHash.value = result['hash'] as String;
          } else {
            error.value = result['error'] as String?;
          }
          isComputing.value = false;
        }).catchError((e) {
          error.value = e.toString();
          isComputing.value = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error viewing hash: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  Future<void> handleRename(BuildContext context, FileItem file, RemoteFileProvider provider) async {
    final newName = await FileOperationDialogs.showRenameDialog(context, file.name);
    if (newName != null && newName.isNotEmpty && newName != file.name) {
      final success = await provider.renameItem(file.path, newName, currentPath);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'Renamed successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to rename');
      }
    }
  }
  
  Future<void> handleDelete(BuildContext context, FileItem file, RemoteFileProvider provider) async {
    final confirmed = await FileOperationDialogs.showDeleteConfirmDialog(context, file.name);
    if (confirmed) {
      final success = await provider.deleteItem(file.path, currentPath);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'Deleted successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to delete');
      }
    }
  }
  
  Future<void> handleUpload(BuildContext context, RemoteFileProvider provider) async {
    final filePath = await FileOperationDialogs.showFilePickerForUpload();
    if (filePath != null) {
      final fileName = filePath.split('/').last.split('\\').last;
      final success = await provider.uploadFile(filePath, currentPath, fileName);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'File uploaded successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to upload file');
      }
    }
  }
  
  Future<void> handleCreateFolder(BuildContext context, RemoteFileProvider provider) async {
    final folderName = await FileOperationDialogs.showCreateFolderDialog(context);
    if (folderName != null && folderName.isNotEmpty) {
      final success = await provider.createFolder(currentPath, folderName);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'Folder created successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to create folder');
      }
    }
  }
  
  Future<void> handleCreateTextFile(BuildContext context, RemoteFileProvider provider) async {
    final fileName = await FileOperationDialogs.showCreateFileDialog(context);
    if (fileName != null && fileName.isNotEmpty) {
      final fullFileName = fileName.endsWith('.txt') ? fileName : '$fileName.txt';
      
      final success = await provider.createTextFile(currentPath, fullFileName);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'Text file created successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to create text file');
      }
    }
  }
  
  Future<void> handleFileDrop(BuildContext context, FileItem draggedFile, FileItem targetFolder, RemoteFileProvider provider) async {
    // Detect if this is a Windows path (contains backslash or drive letter)
    final isWindowsPath = draggedFile.path.contains('\\') || draggedFile.path.contains(':');
    final separator = isWindowsPath ? '\\' : '/';
    
    // Use target folder's path, but if target is root and we have serverRootPath, use that
    String basePath;
    if (targetFolder.path == '/' && provider.serverRootPath != null) {
      // Use the actual server root path
      basePath = provider.serverRootPath!;
    } else {
      basePath = targetFolder.path;
    }
    
    final newPath = '$basePath$separator${draggedFile.name}';
    
    debugPrint('Moving ${draggedFile.path} to $newPath');
    
    final success = await provider.moveItem(draggedFile.path, newPath, currentPath);
    if (!mounted) return;
    
    if (success) {
      FileOperationDialogs.showSuccessSnackbar(
        context, 
        'Moved "${draggedFile.name}" to "${targetFolder.name}"'
      );
    } else {
      FileOperationDialogs.showErrorSnackbar(context, 'Failed to move file');
    }
  }
  
  void handleFileTap(BuildContext context, FileItem file, RemoteFileProvider provider) {
    final ext = file.name.split('.').last.toLowerCase();
    
    // Video files - comprehensive format support
    if (['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', '3gp', '3g2', 'vob', 'ts', 'mts', 'm2ts', 'mpg', 'mpeg', 'ogv'].contains(ext)) {
      // Try to get proxy URL first (for relay mode), fallback to stream URL
      final url = provider.getProxyUrl(file.path) ?? provider.getStreamUrl(file.path);
      
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot play video - not connected')),
        );
        return;
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerView(url: url, fileName: file.name),
        ),
      );
    }
    // Audio files
    else if (['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma', 'opus', 'ape', 'alac', 'aiff', 'aif', 'aifc', 'caf', 'ac3', 'amr', 'oga', 'mogg', 'wv', 'mka'].contains(ext)) {
      // Try to get proxy URL first (for relay mode), fallback to stream URL
      final url = provider.getProxyUrl(file.path) ?? provider.getStreamUrl(file.path);
      
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot play audio - not connected')),
        );
        return;
      }
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioPlayerView(url: url, fileName: file.name),
        ),
      );
    }
    // Image files
    else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif', 'heic', 'heif'].contains(ext)) {
      final url = provider.getStreamUrl(file.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerView(imageUrl: url, fileName: file.name, filePath: file.path),
        ),
      );
    }
    else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open this file type yet')),
      );
    }
  }
  
  void showContextMenu(BuildContext context, FileItem file, RemoteFileProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.label),
            title: const Text('Manage Tags'),
            onTap: () {
              Navigator.pop(context);
              handleManageTags(context, file, provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('View Hash'),
            onTap: () {
              Navigator.pop(context);
              handleViewHash(context, file, provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              handleRename(context, file, provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              handleDelete(context, file, provider);
            },
          ),
        ],
      ),
    );
  }
}
