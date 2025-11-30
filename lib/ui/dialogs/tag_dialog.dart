import 'package:flutter/material.dart';

/// Dialog for managing tags on a file or folder
class TagDialog extends StatefulWidget {
  final String fileName;
  final List<String> currentTags;
  final List<String> availableTags;
  final ValueNotifier<bool>? isHashing;
  final ValueNotifier<double?>? hashProgress;

  const TagDialog({
    super.key,
    required this.fileName,
    required this.currentTags,
    required this.availableTags,
    this.isHashing,
    this.hashProgress,
  });

  @override
  State<TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<TagDialog> {
  late List<String> _selectedTags;
  late Set<String> _originalTags; // Track original tags
  final TextEditingController _newTagController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedTags = List.from(widget.currentTags);
    _originalTags = Set.from(widget.currentTags); // Store original tags
  }

  @override
  void dispose() {
    _newTagController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final trimmedTag = tag.trim().toLowerCase();
    
    // Check if tag is empty
    if (trimmedTag.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag cannot be empty'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Check if tag already exists
    if (_selectedTags.contains(trimmedTag)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tag "$trimmedTag" is already added'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Add the tag
    setState(() {
      _selectedTags.add(trimmedTag);
    });
    _newTagController.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  List<String> get _suggestedTags {
    return widget.availableTags
        .where((tag) => !_selectedTags.contains(tag))
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.isHashing ?? ValueNotifier(false),
      builder: (context, isHashing, child) {
        return AlertDialog(
          title: Text('Manage Tags: ${widget.fileName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show hashing progress if needed
                if (isHashing) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Computing file hash...',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<double?>(
                          valueListenable: widget.hashProgress ?? ValueNotifier(null),
                          builder: (context, progress, child) {
                            return progress != null
                                ? LinearProgressIndicator(value: progress)
                                : const LinearProgressIndicator();
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'You can add/remove tags while waiting. Changes will be saved once hashing completes.',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Current tags
                if (_selectedTags.isNotEmpty) ...[ 
                  const Text(
                    'Current Tags:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedTags.map((tag) {
                      // Check if this is a newly added tag while hashing
                      final isNewTag = !_originalTags.contains(tag);
                      final isQueued = isHashing && isNewTag;
                      
                      return Chip(
                        label: Text(
                          tag,
                          style: isQueued 
                            ? const TextStyle(color: Colors.grey)
                            : null,
                        ),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => _removeTag(tag),
                        backgroundColor: isQueued 
                          ? Colors.grey.shade300
                          : _getTagColor(tag),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Add new tag
                TextField(
                  controller: _newTagController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    labelText: 'Add new tag',
                    hintText: 'Type and press Enter',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _addTag(_newTagController.text),
                    ),
                  ),
                  onSubmitted: _addTag,
                ),
                const SizedBox(height: 16),

                // Suggested tags
                if (_suggestedTags.isNotEmpty) ...[
                  const Text(
                    'Suggested Tags:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedTags.take(10).map((tag) {
                      return ActionChip(
                        label: Text(tag),
                        onPressed: () => _addTag(tag),
                        backgroundColor: _getTagColor(tag).withOpacity(0.3),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint('==> TAG DIALOG: Cancel pressed');
                try {
                  Navigator.pop(context);
                  debugPrint('==> TAG DIALOG: Cancel Navigator.pop completed');
                } catch (e) {
                  debugPrint('==> TAG DIALOG: Cancel Navigator.pop FAILED: $e');
                }
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                debugPrint('==> TAG DIALOG: Save pressed');
                debugPrint('==> Selected tags: $_selectedTags');
                try {
                  Navigator.pop(context, _selectedTags);
                  debugPrint('==> TAG DIALOG: Save Navigator.pop completed');
                } catch (e) {
                  debugPrint('==> TAG DIALOG: Save Navigator.pop FAILED: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Color _getTagColor(String tag) {
    // Simple hash-based color generation
    final hash = tag.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
    ];
    return colors[hash.abs() % colors.length];
  }
}
