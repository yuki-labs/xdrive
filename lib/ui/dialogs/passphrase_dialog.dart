import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PassphraseDialog extends StatefulWidget {
  const PassphraseDialog({super.key});

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _controller = TextEditingController();
  bool _obscureText = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Passphrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This server requires a passphrase to connect.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscureText,
            autofocus: true,
            inputFormatters: [
              // Automatically replace spaces with hyphens
              TextInputFormatter.withFunction((oldValue, newValue) {
                final newText = newValue.text.replaceAll(' ', '-');
                return TextEditingValue(
                  text: newText,
                  selection: TextSelection.collapsed(offset: newText.length),
                );
              }),
            ],
            decoration: InputDecoration(
              labelText: 'Passphrase',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Connect'),
        ),
      ],
    );
  }

  void _submit() {
    final passphrase = _controller.text.trim();
    if (passphrase.isNotEmpty) {
      Navigator.of(context).pop(passphrase);
    }
  }
}
