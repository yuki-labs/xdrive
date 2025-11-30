import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nsd/nsd.dart' as nsd;
import '../server/file_server.dart';
import '../server/discovery_service.dart';
import '../client/remote_file_provider.dart';
import '../client/local_file_provider.dart';
import 'browser_view.dart';
import 'local_browser_view.dart';
import 'settings_screen.dart';
import 'dialogs/passphrase_dialog.dart';
import 'dialogs/room_id_dialog.dart';
import '../models/desktop_mode.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isServerRunning = false;
  int _selectedIndex = 0;
  DesktopMode _desktopMode = DesktopMode.local;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS) {
      // Initialize local file provider first, then start server
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await context.read<LocalFileProvider>().initialize();
        await _startServer();
      });
    } else {
      // Mobile: Start discovery and set up global decryption failure handler
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final provider = context.read<RemoteFileProvider>();
        provider.startDiscovery();
        
        // Set up global decryption failure callback
        provider.onDecryptionFailed = () async {
          debugPrint('Global decryption failure handler triggered');
          if (!mounted) return;
          
          final service = provider.connectedService;
          if (service == null) return;
          
          // Show error and prompt for new passphrase
          final newPassphrase = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Passphrase Changed'),
              content: const Text(
                'The server passphrase has changed. Please enter the current passphrase to continue.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, null);
                    provider.disconnect();
                  },
                  child: const Text('Disconnect'),
                ),
                FilledButton(
                  onPressed: () async {
                    final result = await showDialog<String>(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const PassphraseDialog(),
                    );
                    if (mounted) {
                      Navigator.pop(context, result);
                    }
                  },
                  child: const Text('Enter Passphrase'),
                ),
              ],
            ),
          );
          
          if (newPassphrase != null && mounted) {
            provider.connectToService(service, passphrase: newPassphrase);
          }
        };
      });
    }
  }

  Future<void> _startServer() async {
    final server = context.read<FileServer>();
    final discovery = context.read<DiscoveryService>();
    final localFileProvider = context.read<LocalFileProvider>();
    
    // Wait for LocalFileProvider to initialize if needed
    if (localFileProvider.startDirectory.isEmpty) {
      await localFileProvider.initialize();
    }
    
    await server.start(rootDirectory: localFileProvider.startDirectory);
    await discovery.startAdvertising(server.port);
    setState(() {
      _isServerRunning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows || Platform.isMacOS) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.folder),
                label: Text('Files'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                AppBar(
                  title: const Text('My Desktop'),
                  actions: [
                    if (_isServerRunning)
                      const Chip(
                        avatar: Icon(Icons.check_circle, color: Colors.green),
                        label: Text('Server Running'),
                      )
                  ],
                ),
                // Desktop Mode Selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Mode:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(width: 16),
                      SegmentedButton<DesktopMode>(
                        segments: const [
                          ButtonSegment(
                            value: DesktopMode.local,
                            label: Text('Local'),
                            icon: Icon(Icons.folder, size: 18),
                          ),
                          ButtonSegment(
                            value: DesktopMode.remote,
                            label: Text('Remote'),
                            icon: Icon(Icons.cloud, size: 18),
                          ),
                          ButtonSegment(
                            value: DesktopMode.sync,
                            label: Text('Sync'),
                            icon: Icon(Icons.sync, size: 18),
                          ),
                        ],
                        selected: {_desktopMode},
                        onSelectionChanged: (Set<DesktopMode> newSelection) {
                          setState(() {
                            _desktopMode = newSelection.first;
                            // When switching to remote/sync, start discovery
                            if (_desktopMode != DesktopMode.local) {
                              context.read<RemoteFileProvider>().startDiscovery();
                            } else {
                              context.read<RemoteFileProvider>().stopDiscovery();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                // Content based on mode
                _selectedIndex == 0
                    ? Expanded(
                        child: _buildContentForMode(),
                      )
                    : const Expanded(
                        child: SettingsScreen(),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentForMode() {
    switch (_desktopMode) {
      case DesktopMode.local:
        return const LocalBrowserView();
      
      case DesktopMode.remote:
        return _buildRemoteMode();
      
      case DesktopMode.sync:
        return _buildSyncMode();
    }
  }

  Widget _buildRemoteMode() {
    final provider = context.watch<RemoteFileProvider>();

    if (provider.connectedService != null) {
      return BrowserView(
        onBack: () {
          context.read<RemoteFileProvider>().disconnect();
        },
      );
    }

    // Show discovered hosts
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Discovered Desktop Hosts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: provider.discoveredServices.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Scanning for desktop hosts...'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.discoveredServices.length,
                  itemBuilder: (context, index) {
                    final nsd.Service service = provider.discoveredServices[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.computer, size: 40),
                        title: Text(service.name ?? 'Unknown Host'),
                        subtitle: Text('${service.host}:${service.port}'),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () async {
                          // Check for saved passphrase first
                          String? passphrase = await provider.getSavedPassphrase(service);
                          
                          // If no saved passphrase, show dialog
                          if (passphrase == null) {
                            passphrase = await showDialog<String>(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const PassphraseDialog(),
                            );
                            
                            if (passphrase == null) return; // User cancelled
                          }
                          
                          // Set up callback for decryption failures
                          debugPrint('Registering decryption failure callback...');
                          provider.onDecryptionFailed = () async {
                            debugPrint('Decryption failure callback triggered!');
                            if (context.mounted) {
                              // Show error and prompt for new passphrase
                              final newPassphrase = await showDialog<String>(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => AlertDialog(
                                  title: const Text('Invalid Passphrase'),
                                  content: const Text(
                                    'The saved passphrase is incorrect. The server passphrase may have changed. Please enter the current passphrase.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, null),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () async {
                                        final result = await showDialog<String>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => const PassphraseDialog(),
                                        );
                                        if (context.mounted) {
                                          Navigator.pop(context, result);
                                        }
                                      },
                                      child: const Text('Enter Passphrase'),
                                    ),
                                  ],
                                ),
                              );
                              
                              if (newPassphrase != null && context.mounted) {
                                provider.connectToService(service, passphrase: newPassphrase);
                              }
                            }
                          };
                          
                          provider.connectToService(service, passphrase: passphrase);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSyncMode() {
    final provider = context.watch<RemoteFileProvider>();

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Sync with Desktop Host',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (provider.connectedService == null)
          Expanded(
            child: provider.discoveredServices.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Scanning for desktop hosts...'),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.discoveredServices.length,
                    itemBuilder: (context, index) {
                      final nsd.Service service = provider.discoveredServices[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.sync, size: 40),
                          title: Text(service.name ?? 'Unknown Host'),
                          subtitle: Text('${service.host}:${service.port}'),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () async {
                            // Check for saved passphrase first
                            String? passphrase = await provider.getSavedPassphrase(service);
                            
                            // If no saved passphrase, show dialog
                            if (passphrase == null) {
                              passphrase = await showDialog<String>(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const PassphraseDialog(),
                              );
                              
                              if (passphrase == null) return; // User cancelled
                            }
                            
                            provider.connectToService(service, passphrase: passphrase);
                          },
                        ),
                      );
                    },
                  ),
          )
        else
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sync, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  Text(
                    'Connected to: ${provider.connectedService?.name}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  const Text('Sync feature coming soon...'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<RemoteFileProvider>().disconnect();
                    },
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final provider = context.watch<RemoteFileProvider>();

    if (provider.connectedService != null) {
      return BrowserView(
        onBack: () {
          debugPrint('Mobile BrowserView onBack called, disconnecting...');
          context.read<RemoteFileProvider>().disconnect();
        },
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Connect to Desktop'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.wifi), text: 'Local Network'),
              Tab(icon: Icon(Icons.public), text: 'Internet'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Local Network Tab
            _buildLocalNetworkTab(provider),
            // Internet Tab
            _buildInternetTab(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalNetworkTab(RemoteFileProvider provider) {
    if (provider.discoveredServices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning for desktop hosts...'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: provider.discoveredServices.length,
      itemBuilder: (context, index) {
        final nsd.Service service = provider.discoveredServices[index];
        return ListTile(
          leading: const Icon(Icons.computer),
          title: Text(service.name ?? 'Unknown Host'),
          subtitle: Text('${service.host}:${service.port}'),
          onTap: () async {
            // Check for saved passphrase first
            String? passphrase = await provider.getSavedPassphrase(service);
            
            // If no saved passphrase, show dialog
            if (passphrase == null) {
              passphrase = await showDialog<String>(
                context: context,
                barrierDismissible: false,
                builder: (context) => const PassphraseDialog(),
              );
              
              if (passphrase == null) return; // User cancelled
            }
            
            provider.connectToService(service, passphrase: passphrase);
          },
        );
      },
    );
  }

  Widget _buildInternetTab(RemoteFileProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.public, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Connect via Internet',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Get the Room ID and Passphrase from the desktop host (Settings → Internet Access)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                // Get room ID
                final roomId = await showDialog<String>(
                  context: context,
                  builder: (context) => const RoomIdDialog(),
                );
                
                if (roomId == null || !context.mounted) return;
                
                // Get passphrase
                final passphrase = await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const PassphraseDialog(),
                );
                
                if (passphrase == null || !context.mounted) return;
                
                // Connect via relay
                try {
                  await provider.connectViaRelay(roomId, passphrase);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connection failed: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Enter Room ID'),
            ),
          ],
        ),
      ),
    );
  }
}
