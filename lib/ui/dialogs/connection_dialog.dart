import 'package:flutter/material.dart';

/// Result from connection dialog
class ConnectionResult {
  final String username;
  
  ConnectionResult({required this.username});
  
  // For backward compatibility
  String get identifier => username;
  bool get isUsername => true;
}

/// Dialog to collect username for relay connection
class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _controller = TextEditingController();

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      Navigator.pop(context, ConnectionResult(username: value));
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
            'Enter the username from the desktop host:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'john',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          
          const Text(
            'Get this from Settings → Internet Access on the host',
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
