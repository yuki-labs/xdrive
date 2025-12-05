import 'package:flutter/material.dart';

/// Result from connection dialog
class ConnectionResult {
  final String identifier;
  final bool isUsername; // true = username, false = room ID
  
  ConnectionResult({required this.identifier, required this.isUsername});
}

/// Dialog to collect username or room ID for relay connection
class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _controller = TextEditingController();
  bool _useUsername = true; // Default to username mode

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      Navigator.pop(context, ConnectionResult(
        identifier: _useUsername ? value : value.toLowerCase(),
        isUsername: _useUsername,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect via Internet'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle between username and room ID
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Username'),
                icon: Icon(Icons.person),
              ),
              ButtonSegment(
                value: false,
                label: Text('Room ID'),
                icon: Icon(Icons.meeting_room),
              ),
            ],
            selected: {_useUsername},
            onSelectionChanged: (selection) {
              setState(() => _useUsername = selection.first);
            },
          ),
          const SizedBox(height: 16),
          
          Text(
            _useUsername 
                ? 'Enter the username from the desktop host:'
                : 'Enter the Room ID from the desktop host:',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: _useUsername ? 'Username' : 'Room ID',
              hintText: _useUsername ? 'john' : 'alpha-bravo-charlie',
              border: const OutlineInputBorder(),
              prefixIcon: Icon(_useUsername ? Icons.person : Icons.meeting_room),
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          
          Text(
            _useUsername 
                ? 'Connect using the host\'s username'
                : 'Legacy format: word-word-word',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Next'),
        ),
      ],
    );
  }
}
