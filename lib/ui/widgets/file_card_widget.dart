import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/file_item.dart';
import '../../client/remote_file_provider.dart';

/// A draggable card widget for displaying files and folders
class FileCardWidget extends StatelessWidget {
  final FileItem file;
  final RemoteFileProvider provider;
  final VoidCallback onTap;
  final VoidCallback onShowContextMenu;
  final Function(FileItem dragged, FileItem target) onFileDrop;

  const FileCardWidget({
    super.key,
    required this.file,
    required this.provider,
    required this.onTap,
    required this.onShowContextMenu,
    required this.onFileDrop,
  });

  @override
  Widget build(BuildContext context) {
    final isDir = file.type == FileType.directory;
    final icon = isDir ? Icons.folder : _getFileIcon(file.name);
    final color = isDir ? Colors.amber : Colors.blueGrey;

    final cardContent = GestureDetector(
      onSecondaryTapDown: (details) => onShowContextMenu(),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InkWell(
              onTap: onTap,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Show thumbnail for images, icon for everything else
                    _buildFilePreview(icon, color),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: _buildFileName(context),
                    ),
                    if (!isDir)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          _formatSize(file.size),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    // Tag chips
                    if (file.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0, left: 4.0, right: 4.0),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.center,
                          children: file.tags.take(2).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Menu button
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onShowContextMenu,
              ),
            ),
          ],
        ),
      ),
    );

    // Wrap folders in DragTarget, make both draggable
    if (isDir) {
      return DragTarget<FileItem>(
        onWillAccept: (data) => data != null && data.path != file.path,
        onAccept: (draggedFile) => onFileDrop(draggedFile, file),
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return _buildDraggable(cardContent, icon, color, isHovering);
        },
      );
    } else {
      return _buildDraggable(cardContent, icon, color, false);
    }
  }

  Widget _buildDraggable(Widget cardContent, IconData icon, Color color, bool isHovering) {
    final feedback = Material(
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
    );

    // Use LongPressDraggable on mobile, Draggable on desktop
    if (Platform.isAndroid || Platform.isIOS) {
      return LongPressDraggable<FileItem>(
        data: file,
        delay: const Duration(milliseconds: 500),
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.3, child: cardContent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            border: isHovering ? Border.all(color: Colors.blue, width: 2) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: cardContent,
        ),
      );
    } else {
      return Draggable<FileItem>(
        data: file,
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.3, child: cardContent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            border: isHovering ? Border.all(color: Colors.blue, width: 2) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: cardContent,
        ),
      );
    }
  }

  Widget _buildFileName(BuildContext context) {
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

  Widget _buildFilePreview(IconData fallbackIcon, Color iconColor) {
    final ext = file.name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'tif'].contains(ext);
    final isVideo = ['mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm', 'm4v', '3gp'].contains(ext);
    
    // Fixed height container to ensure consistent alignment
    return SizedBox(
      height: 64,
      child: Center(
        child: (isImage || isVideo) && file.type == FileType.file
            ? _buildThumbnail(fallbackIcon, iconColor)
            : Icon(fallbackIcon, size: 48, color: iconColor),
      ),
    );
  }

  Widget _buildThumbnail(IconData fallbackIcon, Color iconColor) {
    final thumbnailUrl = provider.getThumbnailUrl(file.path);
    
    // Check if using relay mode
    if (thumbnailUrl.startsWith('relay:')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 64,
          child: FutureBuilder<Uint8List?>(
            future: provider.getThumbnailBytes(file.path),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(fallbackIcon, size: 48, color: iconColor);
                    },
                  );
                } else {
                  return Icon(fallbackIcon, size: 48, color: iconColor);
                }
              } else {
                return Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
            },
          ),
        ),
      );
    }
    
    // Normal HTTP mode
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Image.network(
          thumbnailUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // Fallback to icon on error
            return Icon(fallbackIcon, size: 48, color: iconColor);
          },
        ),
      ),
    );
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
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
