import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../client/local_file_provider.dart';
import '../models/file_item.dart';
import 'image_viewer_view.dart';
import 'video_player_view.dart';
import 'views/audio_player_view.dart';
import 'dialogs/file_operation_dialogs.dart';

class LocalBrowserView extends StatefulWidget {
  const LocalBrowserView({super.key});

  @override
  State<LocalBrowserView> createState() => _LocalBrowserViewState();
}

class _LocalBrowserViewState extends State<LocalBrowserView> {
  Timer? _backNavigationTimer;
  Timer? _hapticTimer;

  @override
  void dispose() {
    _cancelBackNavigationTimer();
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _startBackNavigationTimer(LocalFileProvider provider) {
    // Start haptic feedback (mobile only)
    if (_hapticTimer == null && (Platform.isAndroid || Platform.isIOS)) {
      // Immediate first haptic
      HapticFeedback.lightImpact();
      
      // Second buzz just before navigation triggers (at 350ms of 500ms delay)
      _hapticTimer = Timer(const Duration(milliseconds: 350), () {
        HapticFeedback.lightImpact();
      });
    }
    
    // Cancel existing timer and start new one
    _backNavigationTimer?.cancel();
    _backNavigationTimer = Timer(const Duration(milliseconds: 500), () {
      final parentPath = provider.getParentPath();
      if (parentPath != null && mounted) {
        provider.fetchFiles(parentPath);
        _hapticTimer?.cancel();
        _hapticTimer = null;
      }
    });
  }

  void _cancelBackNavigationTimer() {
    _backNavigationTimer?.cancel();
    _backNavigationTimer = null;
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalFileProvider>();
    final files = provider.files;

    return Scaffold(
      appBar: AppBar(
        leading: SizedBox(
          width: 80, // Larger hover area
          child: DragTarget<FileItem>(
            onWillAcceptWithDetails: (details) => true,
            onMove: (details) => _startBackNavigationTimer(provider),
            onLeave: (data) => _cancelBackNavigationTimer(),
            builder: (context, candidateData, rejectedData) {
              return IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  final parentPath = provider.getParentPath();
                  if (parentPath != null) {
                    provider.fetchFiles(parentPath);
                  }
                },
              );
            },
          ),
        ),
        title: Text(provider.currentPath),
      ),
      body: DragTarget<FileItem>(
        onWillAcceptWithDetails: (details) {
          // Accept files being dropped into current directory
          return details.data.path != provider.currentPath;
        },
        onAcceptWithDetails: (details) {
          // Move file to current directory
          final draggedFile = details.data;
          final targetDir = FileItem(
            name: provider.currentPath.split(Platform.pathSeparator).last,
            path: provider.currentPath,
            type: FileType.directory,
            size: 0,
            tags: [],
          );
          _handleFileDrop(context, draggedFile, targetDir, provider);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return Container(
            color: isHovering ? Colors.blue.withOpacity(0.1) : null,
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.8,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return _buildFileCard(file, provider);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new_item',
        onPressed: () {
          // Show popup menu
          showMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              MediaQuery.of(context).size.width - 70,
              MediaQuery.of(context).size.height - 160,
              20,
              20,
            ),
            items: [
              const PopupMenuItem(
                value: 'folder',
                child: Row(
                  children: [
                    Icon(Icons.folder),
                    SizedBox(width: 12),
                    Text('New Folder'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'text_file',
                child: Row(
                  children: [
                    Icon(Icons.description),
                    SizedBox(width: 12),
                    Text('New Text File'),
                  ],
                ),
              ),
            ],
          ).then((value) {
            if (value == 'folder') {
              _handleCreateFolder(context, provider);
            } else if (value == 'text_file') {
              _handleCreateTextFile(context, provider);
            }
          });
        },
        tooltip: 'New Item',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFileCard(FileItem file, LocalFileProvider provider) {
    final isDir = file.type == FileType.directory;
    final icon = isDir ? Icons.folder : _getFileIcon(file.name);
    final color = isDir ? Colors.amber : Colors.blueGrey;

    final cardContent = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isDir) {
            provider.fetchFiles(file.path);
          } else {
            _handleFileTap(context, file);
          }
        },
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Show thumbnail for images/videos, icon for everything else
              _buildLocalFilePreview(file, icon, color),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: _buildFileName(context, file),
              ),
              if (!isDir)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    _formatSize(file.size),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Wrap folders in DragTarget to accept drops
    if (isDir) {
      return DragTarget<FileItem>(
        onWillAccept: (data) {
          // Don't accept dropping onto itself
          return data != null && data.path != file.path;
        },
        onAccept: (draggedFile) {
          _handleFileDrop(context, draggedFile, file, provider);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return Draggable<FileItem>(
            data: file,
            feedback: Material(
              elevation: 4,
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.7,
                child: SizedBox(
                  width: 150,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 48, color: color),
                          const SizedBox(height: 8),
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: cardContent,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                border: isHovering
                    ? Border.all(color: Colors.blue, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: cardContent,
            ),
          );
        },
      );
    } else {
      // Files are draggable but not drop targets
      return Draggable<FileItem>(
        data: file,
        feedback: Material(
          elevation: 4,
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.7,
            child: SizedBox(
              width: 150,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 48, color: color),
                      const SizedBox(height: 8),
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: cardContent,
        ),
        child: cardContent,
      );
    }
  }

  Widget _buildFileName(BuildContext context, FileItem file) {
    // For single-line middle-ellipsis truncation preserving extension
    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = Theme.of(context).textTheme.bodyMedium!;
        final textSpan = TextSpan(text: file.name, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        if (!textPainter.didExceedMaxLines) {
          // Fits in one line, show as-is
          return Text(
            file.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: textStyle,
          );
        }

        // Truncate with middle ellipsis, preserving start and extension
        final parts = file.name.split('.');
        final extension = parts.length > 1 ? '.${parts.last}' : '';
        final nameWithoutExt = parts.length > 1 
            ? parts.sublist(0, parts.length - 1).join('.')
            : file.name;

        // Binary search for the right length
        int start = 1;
        int end = nameWithoutExt.length;
        String truncated = file.name;

        while (start <= end) {
          final mid = (start + end) ~/ 2;
          final testName = '${nameWithoutExt.substring(0, mid)}...$extension';
          final testSpan = TextSpan(text: testName, style: textStyle);
          final testPainter = TextPainter(
            text: testSpan,
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);

          if (testPainter.didExceedMaxLines) {
            end = mid - 1;
          } else {
            truncated = testName;
            start = mid + 1;
          }
        }

        return Text(
          truncated,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: textStyle,
        );
      },
    );
  }

  Widget _buildLocalFilePreview(FileItem file, IconData fallbackIcon, Color iconColor) {
    final ext = file.name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'tif'].contains(ext);
    
    // Fixed height container to ensure consistent alignment
    return SizedBox(
      height: 64,
      child: Center(
        child: isImage && file.type == FileType.file
            ? _buildLocalThumbnail(file, fallbackIcon, iconColor)
            : Icon(fallbackIcon, size: 48, color: iconColor),
      ),
    );
  }

  Widget _buildLocalThumbnail(FileItem file, IconData fallbackIcon, Color iconColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to icon on error
            return Icon(fallbackIcon, size: 48, color: iconColor);
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return frame != null
                ? child
                : Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
          },
        ),
      ),
    );
  }

  void _handleFileTap(BuildContext context, FileItem file) {
    final ext = file.name.split('.').last.toLowerCase();
    
    // Video files - comprehensive format support
    if (['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', '3gp', '3g2', 'vob', 'ts', 'mts', 'm2ts', 'mpg', 'mpeg', 'ogv'].contains(ext)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerView(
            url: Uri.file(file.path).toString(),
            fileName: file.name,
          ),
        ),
      );
    }
    // Audio files
    else if (['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'wma', 'opus', 'ape', 'alac', 'aiff', 'aif', 'aifc', 'caf', 'ac3', 'amr', 'oga', 'mogg', 'wv', 'mka'].contains(ext)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AudioPlayerView(
            url: Uri.file(file.path).toString(),
            fileName: file.name,
          ),
        ),
      );
    }
    // Image files
    else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'ico', 'tiff', 'tif', 'heic', 'heif'].contains(ext)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerView(
            imageUrl: Uri.file(file.path).toString(),
            fileName: file.name,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open this file type yet')),
      );
    }
  }

  Future<void> _handleFileDrop(BuildContext context, FileItem draggedFile, FileItem targetFolder, LocalFileProvider provider) async {
    // Calculate new path: targetFolder.path + draggedFile.name
    final newPath = '${targetFolder.path}${Platform.pathSeparator}${draggedFile.name}';
    
    final success = await provider.moveItem(draggedFile.path, newPath);
    if (!mounted) return;
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved "${draggedFile.name}" to "${targetFolder.name}"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to move file')),
      );
    }
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'mkv':
      case 'mov':
        return Icons.movie;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'mp3':
      case 'wav':
        return Icons.music_note;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _handleCreateFolder(BuildContext context, LocalFileProvider provider) async {
    final folderName = await FileOperationDialogs.showCreateFolderDialog(context);
    if (folderName != null && folderName.isNotEmpty) {
      final success = await provider.createFolder(folderName);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'Folder created successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to create folder');
      }
    }
  }

  Future<void> _handleCreateTextFile(BuildContext context, LocalFileProvider provider) async {
    final fileName = await FileOperationDialogs.showCreateFileDialog(context);
    if (fileName != null && fileName.isNotEmpty) {
      // Ensure .txt extension
      final fullFileName = fileName.endsWith('.txt') ? fileName : '$fileName.txt';
      
      final success = await provider.createTextFile(fullFileName);
      if (!mounted) return;
      
      if (success) {
        FileOperationDialogs.showSuccessSnackbar(context, 'Text file created successfully');
      } else {
        FileOperationDialogs.showErrorSnackbar(context, 'Failed to create text file');
      }
    }
  }
}
