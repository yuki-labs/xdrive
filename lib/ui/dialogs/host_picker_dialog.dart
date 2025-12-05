import 'package:flutter/material.dart';

/// Dialog to pick which host device to connect to
class HostPickerDialog extends StatelessWidget {
  final List<String> hosts;
  final String username;

  const HostPickerDialog({
    super.key,
    required this.hosts,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Select Device for "$username"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Multiple devices are available. Choose which one to connect to:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          ...hosts.map((host) => ListTile(
            leading: const Icon(Icons.computer),
            title: Text(host),
            onTap: () => Navigator.pop(context, host),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          )).toList(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
