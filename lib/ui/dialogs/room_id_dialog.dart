import 'package:flutter/material.dart';

/// Dialog to collect room ID for relay connection
class RoomIdDialog extends StatefulWidget {
  const RoomIdDialog({super.key});

  @override
  State<RoomIdDialog> createState() => _RoomIdDialogState();
}

class _RoomIdDialogState extends State<RoomIdDialog> {
  final _controller = TextEditingController();

  void _submit() {
    final roomId = _controller.text.trim().toLowerCase();
    if (roomId.isNotEmpty) {
      Navigator.pop(context, roomId);
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
          const Text(
            'Enter the Room ID from the desktop host:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Room ID',
              hintText: 'alpha-bravo-charlie',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.meeting_room),
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Format: word-word-word',
            style: TextStyle(fontSize: 12, color: Colors.grey),
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
