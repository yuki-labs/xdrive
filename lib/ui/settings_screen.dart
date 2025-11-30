import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../server/file_server.dart';
import '../client/local_file_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
      return 'Not found';
    } catch (e) {
      return 'Error: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileServer = context.read<FileServer>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: FutureBuilder<String>(
        future: _getLocalIpAddress(),
        builder: (context, snapshot) {
          final ipAddress = snapshot.data ?? 'Loading...';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        context,
                        'Status',
                        'Running',
                        Icons.check_circle,
                        Colors.green,
                      ),
                      const Divider(),
                      _buildInfoRow(
                        context,
                        'Port',
                        fileServer.port.toString(),
                        Icons.settings_ethernet,
                        null,
                      ),
                      const Divider(),
                      _buildInfoRow(
                        context,
                        'IP Address',
                        ipAddress,
                        Icons.computer,
                        null,
                        onTap: ipAddress != 'Loading...' && ipAddress != 'Not found'
                            ? () {
                                Clipboard.setData(ClipboardData(text: ipAddress));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('IP address copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            : null,
                      ),
                      const Divider(),
                      _buildInfoRow(
                        context,
                        'Connection URL',
                        'http://$ipAddress:${fileServer.port}',
                        Icons.link,
                        null,
                        onTap: ipAddress != 'Loading...' && ipAddress != 'Not found'
                            ? () {
                                final url = 'http://$ipAddress:${fileServer.port}';
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URL copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            : null,
                      ),
                      if (fileServer.passphrase != null) ...[
                        const Divider(),
                        _buildInfoRow(
                          context,
                          'Passphrase',
                          fileServer.passphrase!,
                          Icons.key,
                          Colors.amber,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: fileServer.passphrase!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Passphrase copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              // Show confirmation dialog
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Regenerate Passphrase?'),
                                  content: const Text(
                                    'This will create a new passphrase. All connected guests will need the new passphrase to reconnect.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Regenerate'),
                                    ),
                                  ],
                                ),
                              );
                              
                              if (confirmed == true && context.mounted) {
                                await fileServer.regeneratePassphrase();
                                
                                if (mounted) {
                                  setState(() {}); // Rebuild to show new passphrase
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Passphrase regenerated to: ${fileServer.passphrase}'),
                                        duration: const Duration(seconds: 4),
                                        action: SnackBarAction(
                                          label: 'Copy',
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: fileServer.passphrase!));
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Regenerate Passphrase'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Internet Access Section
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.public, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Internet Access',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Enable Internet Access'),
                        subtitle: Text(
                          fileServer.relayMode
                              ? 'Guests can connect from anywhere'
                              : 'Only local network access',
                        ),
                        value: fileServer.relayMode,
                        onChanged: (value) async {
                          if (value) {
                            // Enable relay
                            try {
                              final roomId = await fileServer.enableRelayMode();
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Internet access enabled! Room ID: $roomId'),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to enable: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          } else {
                            // Disable relay
                            await fileServer.disableRelayMode();
                            if (mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Internet access disabled')),
                              );
                            }
                          }
                        },
                      ),
                      if (fileServer.relayRoomId != null) ...[
                        const Divider(),
                        _buildInfoRow(
                          context,
                          'Room ID',
                          fileServer.relayRoomId!,
                          Icons.meeting_room,
                          Colors.green,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: fileServer.relayRoomId!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Room ID copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Share this Room ID and Passphrase with guests to allow them to connect over the internet.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'File Browser',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Consumer<LocalFileProvider>(
                        builder: (context, provider, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Start Directory',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          provider.startDirectory.isEmpty
                                              ? 'Not set'
                                              : provider.startDirectory,
                                          style: Theme.of(context).textTheme.bodySmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
                                      if (selectedDirectory != null) {
                                        provider.setStartDirectory(selectedDirectory);
                                        // Update the server's root directory without restart
                                        fileServer.updateRootDirectory(selectedDirectory);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Start directory updated to: $selectedDirectory'),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.folder_open, size: 18),
                                    label: const Text('Choose'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'This directory will be shown when the app starts',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile Connection',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'To connect from your mobile device:\n'
                        '1. Ensure both devices are on the same WiFi network\n'
                        '2. Open the app on your mobile device\n'
                        '3. Look for "SpacedriveHost" in the discovered hosts\n'
                        '4. Tap to connect and browse files',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Spacedrive Clone v1.0.0\n'
                        'A cross-platform file browser and server',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color? iconColor, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.end,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.copy, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
