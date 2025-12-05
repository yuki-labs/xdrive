import 'package:flutter/material.dart';

/// Result from username setup dialog
class UsernameSetupResult {
  final String username;
  final String? customDeviceName;

  UsernameSetupResult({required this.username, this.customDeviceName});
}

/// Dialog for host to set up username-based relay mode
class UsernameSetupDialog extends StatefulWidget {
  final String defaultDeviceName;

  const UsernameSetupDialog({
    super.key,
    required this.defaultDeviceName,
  });

  @override
  State<UsernameSetupDialog> createState() => _UsernameSetupDialogState();
}

class _UsernameSetupDialogState extends State<UsernameSetupDialog> {
  final _usernameController = TextEditingController();
  final _deviceNameController = TextEditingController();
  bool _useCustomDeviceName = false;

  @override
  void initState() {
    super.initState();
    _deviceNameController.text = widget.defaultDeviceName;
  }

  void _submit() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return;

    Navigator.pop(context, UsernameSetupResult(
      username: username,
      customDeviceName: _useCustomDeviceName ? _deviceNameController.text.trim() : null,
    ));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set Up Remote Access'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a username that clients will use to connect:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _usernameController,
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
              'This will be shared with mobile devices',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            
            // Device name section
            Row(
              children: [
                Checkbox(
                  value: _useCustomDeviceName,
                  onChanged: (value) {
                    setState(() => _useCustomDeviceName = value ?? false);
                  },
                ),
                const Text('Custom device name'),
              ],
            ),
            if (_useCustomDeviceName) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name',
                  hintText: 'My Desktop',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Helps identify this device if you have multiple',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enable'),
        ),
      ],
    );
  }
}
