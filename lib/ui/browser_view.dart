import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../client/remote_file_provider.dart';
import '../models/file_item.dart';
import 'widgets/file_card_widget.dart';
import 'mixins/file_operations_handler.dart';

class BrowserView extends StatefulWidget {
  final VoidCallback onBack;

  const BrowserView({super.key, required this.onBack});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> with FileOperationsHandler {
  String _currentPath = '/';
  final List<String> _pathHistory = ['/'];
  String? _activeFilterTag;
  Timer? _backNavigationTimer;
  Timer? _hapticTimer;

  @override
  String get currentPath => _currentPath;

  @override
  void dispose() {
    _cancelBackNavigationTimer();
    _hapticTimer?.cancel();
    super.dispose();
  }

  void _startBackNavigationTimer(RemoteFileProvider provider) {
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
      if (_pathHistory.length > 1 && mounted) {
        setState(() {
          _pathHistory.removeLast();
          _currentPath = _pathHistory.last;
        });
        provider.fetchFiles(_currentPath);
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
  void refreshFiles() {
    final provider = context.read<RemoteFileProvider>();
    provider.fetchFiles(_currentPath);
  }
  
  List<FileItem> _getFilteredFiles(List<FileItem> allFiles) {
    if (_activeFilterTag == null) return allFiles;
    return allFiles.where((file) => file.tags.contains(_activeFilterTag)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RemoteFileProvider>();
    final allFiles = provider.files;
    final files = _getFilteredFiles(allFiles);

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        
        // Handle back button
        if (_pathHistory.length > 1) {
          setState(() {
            _pathHistory.removeLast();
            _currentPath = _pathHistory.last;
          });
          provider.fetchFiles(_currentPath);
        } else {
          widget.onBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: SizedBox(
            width: 80, // Larger hover area
            child: DragTarget<FileItem>(
              onWillAcceptWithDetails: (details) {
                // Accept any dragged file to enable hover detection
                return true;
              },
              onMove: (details) {
                // Navigate back when user hovers for a moment
                _startBackNavigationTimer(provider);
              },
              onLeave: (data) {
                _cancelBackNavigationTimer();
              },
              builder: (context, candidateData, rejectedData) {
                return IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (_pathHistory.length > 1) {
                      setState(() {
                        _pathHistory.removeLast();
                        _currentPath = _pathHistory.last;
                      });
                      provider.fetchFiles(_currentPath);
                    } else {
                      widget.onBack();
                    }
                  },
                );
              },
            ),
          ),
          title: _activeFilterTag == null
              ? Text(_currentPath)
              : Row(
                  children: [
                    Expanded(child: Text(_currentPath)),
                    Chip(
                      label: Text('Filter: $_activeFilterTag'),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => _activeFilterTag = null);
                      },
                      backgroundColor: Colors.blue.withOpacity(0.2),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _showSearchDialog(context, provider),
              tooltip: 'Filter by tags',
            ),
          ],
        ),
        body: DragTarget<FileItem>(
          onWillAcceptWithDetails: (details) {
            // Accept files being dropped into current directory
            return details.data.path != _currentPath;
          },
          onAcceptWithDetails: (details) {
            // Move file to current directory
            final draggedFile = details.data;
            final targetDir = FileItem(
              name: _currentPath.split('/').last.isEmpty ? '/' : _currentPath.split('/').last,
              path: _currentPath,
              type: FileType.directory,
              size: 0,
              tags: [],
            );
            handleFileDrop(context, draggedFile, targetDir, provider);
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
                  return FileCardWidget(
                    file: file,
                    provider: provider,
                    onTap: () {
                      if (file.type == FileType.directory) {
                        setState(() {
                          _pathHistory.add(file.path);
                          _currentPath = file.path;
                        });
                        provider.fetchFiles(file.path);
                      } else {
                        handleFileTap(context, file, provider);
                      }
                    },
                    onShowContextMenu: () => showContextMenu(context, file, provider),
                    onFileDrop: (dragged, target) {
                      handleFileDrop(context, dragged, target, provider);
                    },
                  );
                },
              ),
            );
          },
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'upload',
              onPressed: () => handleUpload(context, provider),
              tooltip: 'Upload File',
              child: const Icon(Icons.upload_file),
            ),
            const SizedBox(height: 8),
            FloatingActionButton(
              heroTag: 'new_item',
              onPressed: () => _showNewItemMenu(context, provider),
              tooltip: 'New Item',
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewItemMenu(BuildContext context, RemoteFileProvider provider) {
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
        handleCreateFolder(context, provider);
      } else if (value == 'text_file') {
        handleCreateTextFile(context, provider);
      }
    });
  }

  Future<void> _showSearchDialog(BuildContext context, RemoteFileProvider provider) async {
    final availableTags = await provider.getAllTags();
    
    if (!mounted) return;
    
    if (availableTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tags available yet. Add some tags first!')),
      );
      return;
    }

    final selectedTag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Tag'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableTags.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.clear),
                  title: const Text('Show All Files'),
                  onTap: () => Navigator.pop(context, null),
                );
              }
              
              final tag = availableTags[index - 1];
              return ListTile(
                leading: const Icon(Icons.label),
                title: Text(tag),
                onTap: () => Navigator.pop(context, tag),
              );
            },
          ),
        ),
      ),
    );

    if (selectedTag != null && mounted) {
      setState(() => _activeFilterTag = selectedTag);
    } else if (selectedTag == null && mounted) {
      setState(() => _activeFilterTag = null);
    }
  }
}
