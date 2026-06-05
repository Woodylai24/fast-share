import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fast_share_mobile/models/connection_entry.dart';
import 'package:fast_share_mobile/services/connection_history.dart';
import 'package:fast_share_mobile/services/notifications.dart';
import 'package:fast_share_mobile/screens/connecting_screen.dart';
import 'package:fast_share_mobile/screens/settings_screen.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';
import 'package:fast_share_mobile/widgets/qr_scanner.dart';

class HomeScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const HomeScreen({super.key, required this.themeNotifier});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();
  final FocusNode _ipFocusNode = FocusNode();
  List<ConnectionEntry> _connectionHistory = [];
  ConnectionEntry? _selectedConnection;
  bool _isLoading = true;
  bool _isAutoConnecting = false;
  String? _currentNetworkName;
  static bool _autoConnectAttempted =
      false; // Track if auto-connect was attempted in this app session

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissions();
    _loadHistoryAndAutoConnect();
  }

  Future<void> _loadHistoryAndAutoConnect() async {
    // Load connection history
    final history = await ConnectionHistoryService.getConnectionHistory();
    debugPrint('[DEBUG] Connection history loaded: ${history.length} entries');
    for (final entry in history) {
      debugPrint(
        '[DEBUG] History entry: ${entry.ip}:${entry.port}, network: ${entry.networkName}',
      );
    }

    // Get current network name
    final networkInfo = NetworkInfo();
    try {
      _currentNetworkName = await networkInfo.getWifiName();
      debugPrint('[DEBUG] Current WiFi name: "$_currentNetworkName"');
    } catch (e) {
      debugPrint('[DEBUG] Could not get network name: $e');
    }

    setState(() {
      _connectionHistory = history;
      _isLoading = false;
    });

    // Set default selection to last connected IP
    if (history.isNotEmpty) {
      _selectedConnection = history.first;
      _ipController.text = history.first.displayName;
    }

    // Auto-connect if network matches
    await _attemptAutoConnect();
  }

  Future<void> _attemptAutoConnect() async {
    // Only attempt auto-connect once per app session
    if (_autoConnectAttempted) {
      debugPrint(
        '[DEBUG] Auto-connect already attempted in this session, skipping',
      );
      return;
    }
    _autoConnectAttempted = true;

    // Check auto-connect setting
    final autoConnectOnLaunch = await SettingsService.getAutoConnectOnLaunch();
    if (!autoConnectOnLaunch) {
      debugPrint(
        '[DEBUG] Auto-connect on launch is disabled, skipping auto-connect',
      );
      return;
    }

    if (_connectionHistory.isEmpty) {
      debugPrint('[DEBUG] No connection history, skipping auto-connect');
      return;
    }

    final lastConnection = _connectionHistory.first;
    final lastNetworkName = await ConnectionHistoryService.getLastNetworkName();

    debugPrint('[DEBUG] Last network name from storage: "$lastNetworkName"');
    debugPrint('[DEBUG] Current network name: "$_currentNetworkName"');
    debugPrint(
      '[DEBUG] Last connection IP: ${lastConnection.ip}:${lastConnection.port}',
    );

    // Check if current network matches the last connected network
    final bool networkMatches;
    if (_currentNetworkName != null && lastNetworkName != null) {
      // Normalize network names by removing quotes
      final normalizedCurrent = _currentNetworkName!.replaceAll('"', '');
      final normalizedLast = lastNetworkName.replaceAll('"', '');
      networkMatches = normalizedCurrent == normalizedLast;
      debugPrint(
        '[DEBUG] Normalized comparison: "$normalizedCurrent" vs "$normalizedLast" = $networkMatches',
      );
    } else if (_currentNetworkName == null && lastNetworkName == null) {
      networkMatches = true;
      debugPrint('[DEBUG] Both network names are null, allowing auto-connect');
    } else {
      networkMatches = false;
      debugPrint('[DEBUG] One network name is null, other is not - no match');
    }

    if (networkMatches) {
      debugPrint(
        '[DEBUG] Network matches! Auto-connecting to ${lastConnection.ip}',
      );

      setState(() {
        _isAutoConnecting = true;
      });

      // Navigate to connecting screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConnectingScreen(
              ip: lastConnection.ip,
              port: lastConnection.port,
              httpPort: lastConnection.httpPort,
              themeNotifier: widget.themeNotifier,
            ),
          ),
        );
      }
    }
  }

  Future<void> _requestNotificationPermissions() async {
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
  }

  void _handleConnect() {
    final text = _ipController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    // Parse IP and port from text (format: ip:port or just ip)
    String ip;
    int port = 8080; // Default WebSocket port
    int httpPort = 8081; // Default HTTP port

    if (text.contains(':')) {
      final parts = text.split(':');
      ip = parts[0];
      port = int.tryParse(parts[1]) ?? 8080;
    } else {
      ip = text;
    }

    // If selected from history, use stored ports
    if (_selectedConnection != null && _selectedConnection!.ip == ip) {
      port = _selectedConnection!.port;
      httpPort = _selectedConnection!.httpPort;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ConnectingScreen(
              ip: ip,
              port: port,
              httpPort: httpPort,
              themeNotifier: widget.themeNotifier,
            ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _ipFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isAutoConnecting) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fast Share'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(
                      themeNotifier: widget.themeNotifier,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fast Share'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    themeNotifier: widget.themeNotifier,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phonelink, size: 100, color: Colors.blue),
              const SizedBox(height: 30),

              // Connection dropdown / text field
              Autocomplete<ConnectionEntry>(
                initialValue: TextEditingValue(
                  text: _selectedConnection?.displayName ?? '',
                ),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _connectionHistory;
                  }
                  return _connectionHistory.where(
                    (entry) =>
                        entry.ip.contains(textEditingValue.text) ||
                        entry.displayName.contains(textEditingValue.text),
                  );
                },
                displayStringForOption: (ConnectionEntry entry) =>
                    entry.displayName,
                onSelected: (ConnectionEntry entry) {
                  setState(() {
                    _selectedConnection = entry;
                    _ipController.text = entry.displayName;
                  });
                },
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController fieldTextEditingController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      // Sync with our controller
                      fieldTextEditingController.addListener(() {
                        _ipController.text = fieldTextEditingController.text;
                      });

                      return TextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        decoration: InputDecoration(
                          labelText: 'IP Address',
                          hintText: 'Enter IP or select from history',
                          border: const OutlineInputBorder(),
                          suffixIcon: _connectionHistory.isNotEmpty
                              ? PopupMenuButton<ConnectionEntry>(
                                  icon: const Icon(Icons.arrow_drop_down),
                                  itemBuilder: (context) {
                                    return _connectionHistory.map((entry) {
                                      return PopupMenuItem<ConnectionEntry>(
                                        value: entry,
                                        child: ListTile(
                                          leading: const Icon(Icons.history),
                                          title: Text(entry.displayName),
                                          subtitle: Text(
                                            'Last: ${_formatDate(entry.lastConnected)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _removeFromHistory(entry);
                                            },
                                          ),
                                        ),
                                      );
                                    }).toList();
                                  },
                                  onSelected: (entry) {
                                    fieldTextEditingController.text =
                                        entry.displayName;
                                    setState(() {
                                      _selectedConnection = entry;
                                    });
                                  },
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _handleConnect(),
                        keyboardType: TextInputType.text,
                      );
                    },
                optionsViewBuilder:
                    (
                      BuildContext context,
                      AutocompleteOnSelected<ConnectionEntry> onSelected,
                      Iterable<ConnectionEntry> options,
                    ) {
                      return Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final entry = options.elementAt(index);
                              return ListTile(
                                leading: const Icon(Icons.history),
                                title: Text(entry.displayName),
                                subtitle: Text(
                                  'Last: ${_formatDate(entry.lastConnected)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () => onSelected(entry),
                              );
                            },
                          ),
                        ),
                      );
                    },
              ),

              const SizedBox(height: 16),

              // Connect button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleConnect,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Divider with "or"
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 30),

              // Scan QR button
              ElevatedButton.icon(
                onPressed: () async {
                  // Request Camera Permission
                  if (await Permission.camera.request().isGranted) {
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ScannerScreen(themeNotifier: widget.themeNotifier),
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Camera permission required'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _removeFromHistory(ConnectionEntry entry) async {
    await ConnectionHistoryService.removeConnection(entry.ip);
    final history = await ConnectionHistoryService.getConnectionHistory();
    setState(() {
      _connectionHistory = history;
      if (_selectedConnection?.ip == entry.ip) {
        _selectedConnection = history.isNotEmpty ? history.first : null;
        _ipController.text = _selectedConnection?.displayName ?? '';
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection removed from history')),
      );
    }
  }
}
