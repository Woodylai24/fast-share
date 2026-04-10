import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'firebase_options.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Connection history entry
class ConnectionEntry {
  final String ip;
  final int port;
  final int httpPort;
  final String? networkName;
  final DateTime lastConnected;

  ConnectionEntry({
    required this.ip,
    required this.port,
    required this.httpPort,
    this.networkName,
    DateTime? lastConnected,
  }) : lastConnected = lastConnected ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'httpPort': httpPort,
    'networkName': networkName,
    'lastConnected': lastConnected.toIso8601String(),
  };

  factory ConnectionEntry.fromJson(Map<String, dynamic> json) {
    return ConnectionEntry(
      ip: json['ip'] as String,
      port: json['port'] as int,
      httpPort: json['httpPort'] as int? ?? 8081,
      networkName: json['networkName'] as String?,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
    );
  }

  String get displayName => '$ip:$port';
}

/// Service to manage connection history
class ConnectionHistoryService {
  static const String _historyKey = 'connection_history';
  static const String _lastNetworkKey = 'last_network_name';
  static const int _maxHistorySize = 10;

  static Future<SharedPreferences> get _prefs async {
    return await SharedPreferences.getInstance();
  }

  /// Save a connection to history
  static Future<void> saveConnection(ConnectionEntry entry) async {
    final prefs = await _prefs;
    final history = await getConnectionHistory();

    // Remove existing entry with same IP
    history.removeWhere((e) => e.ip == entry.ip);

    // Add new entry at the beginning
    history.insert(0, entry);

    // Keep only the last _maxHistorySize entries
    if (history.length > _maxHistorySize) {
      history.removeRange(_maxHistorySize, history.length);
    }

    // Save to preferences
    final jsonList = history.map((e) => e.toJson()).toList();
    await prefs.setString(_historyKey, jsonEncode(jsonList));

    // Save network name
    if (entry.networkName != null) {
      await prefs.setString(_lastNetworkKey, entry.networkName!);
    }
  }

  /// Get connection history
  static Future<List<ConnectionEntry>> getConnectionHistory() async {
    final prefs = await _prefs;
    final jsonString = prefs.getString(_historyKey);

    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => ConnectionEntry.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading connection history: $e');
      return [];
    }
  }

  /// Get the last connected entry
  static Future<ConnectionEntry?> getLastConnection() async {
    final history = await getConnectionHistory();
    return history.isNotEmpty ? history.first : null;
  }

  /// Get the last network name
  static Future<String?> getLastNetworkName() async {
    final prefs = await _prefs;
    return prefs.getString(_lastNetworkKey);
  }

  /// Remove a connection from history
  static Future<void> removeConnection(String ip) async {
    final prefs = await _prefs;
    final history = await getConnectionHistory();

    history.removeWhere((e) => e.ip == ip);

    final jsonList = history.map((e) => e.toJson()).toList();
    await prefs.setString(_historyKey, jsonEncode(jsonList));
  }

  /// Clear all history
  static Future<void> clearHistory() async {
    final prefs = await _prefs;
    await prefs.remove(_historyKey);
    await prefs.remove(_lastNetworkKey);
  }
}

/// Message storage service for persistence
class MessageStorageService {
  static const String _messagesKey = 'saved_messages';
  static const int _maxMessages = 100;

  static Future<void> saveMessages(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = messages.map((m) => m.toJson()).toList();
    await prefs.setString(_messagesKey, jsonEncode(jsonList));
  }

  static Future<List<Message>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_messagesKey);

    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading messages: $e');
      return [];
    }
  }

  static Future<void> clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesKey);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final String? payload = response.payload;
      if (payload != null) {
        if (payload.startsWith('COPY:')) {
          final String textToCopy = payload.substring(5);
          await Clipboard.setData(ClipboardData(text: textToCopy));
        } else if (payload.startsWith('OPEN_APP:')) {
          // Open the app when notification is tapped
          // The app will automatically reconnect via lifecycle observer
          debugPrint('[DEBUG] Notification tapped, opening app');
        } else {
          final Uri url = Uri.parse(payload);
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    },
  );

  // Request permission for notifications (iOS)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get FCM token
  final fcmToken = await FirebaseMessaging.instance.getToken();
  debugPrint('[DEBUG] FCM Token: $fcmToken');

  // Save FCM token for later use
  final prefs = await SharedPreferences.getInstance();
  if (fcmToken != null) {
    await prefs.setString('fcm_token', fcmToken);
  }

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    debugPrint('[DEBUG] FCM Token refreshed: $newToken');
    prefs.setString('fcm_token', newToken);
  });

  // Handle background messages
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint(
      '[DEBUG] Received foreground message: ${message.notification?.title}',
    );
    if (message.notification != null) {
      _showLocalNotification(
        message.notification!.title ?? 'Fast Share',
        message.notification!.body ?? '',
        payload: message.data['payload'],
      );
    }
  });

  // Handle message when app is opened from background via notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('[DEBUG] Message opened app: ${message.notification?.title}');
    // The app will automatically reconnect via lifecycle observer
  });

  runApp(const FastShareApp());
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[DEBUG] Background message: ${message.notification?.title}');
}

// Helper function to show local notification
Future<void> _showLocalNotification(
  String title,
  String body, {
  String? payload,
}) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'fast_share_channel',
        'Fast Share Notifications',
        channelDescription: 'Notifications for Fast Share messages and files',
        importance: Importance.max,
        priority: Priority.high,
      );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecond,
    title,
    body,
    platformChannelSpecifics,
    payload: payload ?? 'OPEN_APP:',
  );
}

class FastShareApp extends StatelessWidget {
  const FastShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fast Share Mobile',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
    // Also try to match if both are null (VPN case or permission issue)
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
      // Both null - could be VPN or permission issue, allow auto-connect
      networkMatches = true;
      debugPrint('[DEBUG] Both network names are null, allowing auto-connect');
    } else {
      // One is null, other is not
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
            ConnectingScreen(ip: ip, port: port, httpPort: httpPort),
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
        appBar: AppBar(title: const Text('Fast Share')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fast Share')),
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
                          builder: (context) => const ScannerScreen(),
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

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        onDetect: (capture) {
          if (hasScanned) return;
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              try {
                final data = jsonDecode(barcode.rawValue!);
                if (data['ip'] != null && data['port'] != null) {
                  setState(() {
                    hasScanned = true;
                  });
                  // Stop scanning and navigate to Connecting Screen
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConnectingScreen(
                        ip: data['ip'],
                        port: data['port'],
                        httpPort: data['httpPort'] ?? 8081,
                      ),
                    ),
                  );
                  return; // Detect only one
                }
              } catch (e) {
                // Not our QR code
              }
            }
          }
        },
      ),
    );
  }
}

/// Screen shown while attempting to connect to PC
/// Validates the connection before showing the main ConnectedScreen
class ConnectingScreen extends StatefulWidget {
  final String ip;
  final int port;
  final int httpPort;

  const ConnectingScreen({
    super.key,
    required this.ip,
    required this.port,
    required this.httpPort,
  });

  @override
  State<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends State<ConnectingScreen> {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _errorMessage;
  bool _isConnecting = true;
  bool _handshakeReceived = false;

  @override
  void initState() {
    super.initState();
    _attemptConnection();
  }

  Future<void> _attemptConnection() async {
    final wsUrl = Uri.parse('ws://${widget.ip}:${widget.port}');
    debugPrint('[DEBUG] Attempting to connect to: $wsUrl');

    try {
      _channel = WebSocketChannel.connect(wsUrl);

      // Set up a timeout for connection
      final timeout = Timer(const Duration(seconds: 10), () {
        if (!_handshakeReceived && mounted) {
          debugPrint('[DEBUG] Connection timeout - no handshake received');
          _cleanup();
          setState(() {
            _isConnecting = false;
            _errorMessage =
                'Connection timeout. Make sure you are on the same WiFi network as the PC.';
          });
        }
      });

      // Listen for messages (single-subscription stream, so we need to handle carefully)
      _subscription = _channel!.stream.listen(
        (message) async {
          debugPrint('[DEBUG] Received: $message');
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'handshake') {
              _handshakeReceived = true;
              timeout.cancel();
              debugPrint('[DEBUG] Handshake received from PC');

              if (mounted) {
                // Save connection to history
                await _saveConnectionToHistory();

                // Cancel this subscription before navigating
                // ConnectedScreen will create its own connection
                _subscription?.cancel();
                _channel?.sink.close();

                // Navigate to ConnectedScreen (it will create a new connection)
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConnectedScreen(
                        ip: widget.ip,
                        port: widget.port,
                        httpPort: widget.httpPort,
                      ),
                    ),
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('[DEBUG] Failed to parse: $e');
          }
        },
        onError: (error) {
          debugPrint('[DEBUG] WebSocket error: $error');
          timeout.cancel();
          _cleanup();
          if (mounted) {
            setState(() {
              _isConnecting = false;
              _errorMessage = 'Connection failed: $error';
            });
          }
        },
        onDone: () {
          debugPrint('[DEBUG] WebSocket closed');
          timeout.cancel();
          if (!_handshakeReceived && mounted) {
            _cleanup();
            setState(() {
              _isConnecting = false;
              _errorMessage =
                  'Connection closed unexpectedly. Check if the PC app is running.';
            });
          }
        },
      );

      // Send handshake to PC
      _channel!.sink.add(jsonEncode({'type': 'handshake', 'device': 'Mobile'}));
      debugPrint('[DEBUG] Handshake sent to PC');
    } catch (e) {
      debugPrint('[DEBUG] Failed to create WebSocket: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = 'Failed to connect: $e';
        });
      }
    }
  }

  void _cleanup() {
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _saveConnectionToHistory() async {
    try {
      // Get current network name
      String? networkName;
      try {
        final networkInfo = NetworkInfo();
        networkName = await networkInfo.getWifiName();
        debugPrint('[DEBUG] Saving connection - WiFi name: "$networkName"');
      } catch (e) {
        debugPrint('[DEBUG] Could not get network name when saving: $e');
      }

      final entry = ConnectionEntry(
        ip: widget.ip,
        port: widget.port,
        httpPort: widget.httpPort,
        networkName: networkName,
      );

      await ConnectionHistoryService.saveConnection(entry);
      debugPrint(
        '[DEBUG] Connection saved to history: ${entry.ip}:${entry.port}, network: ${entry.networkName}',
      );
    } catch (e) {
      debugPrint('[DEBUG] Failed to save connection to history: $e');
    }
  }

  @override
  void dispose() {
    // Only close if we're not navigating to ConnectedScreen
    if (!_handshakeReceived) {
      _cleanup();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connecting...')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text('Connecting to ${widget.ip}:${widget.port}...'),
              const SizedBox(height: 10),
              const Text(
                'Make sure you are on the same WiFi network',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Error state
    return Scaffold(
      appBar: AppBar(title: const Text('Connection Failed')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
                label: const Text('Back to Home'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConnectingScreen(
                        ip: widget.ip,
                        port: widget.port,
                        httpPort: widget.httpPort,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Message types enum
enum MessageType { text, file, image }

/// Message model class
class Message {
  final String id;
  final MessageType type;
  final String content;
  final String? url;
  final String sender; // 'PC' or 'Me' or 'System'
  final String? filename;
  final DateTime timestamp;

  Message({
    String? id,
    required this.type,
    required this.content,
    this.url,
    required this.sender,
    this.filename,
    DateTime? timestamp,
  }) : id =
           id ??
           '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}',
       timestamp = timestamp ?? DateTime.now();

  /// Create a text message
  factory Message.text({required String content, required String sender}) {
    return Message(type: MessageType.text, content: content, sender: sender);
  }

  /// Create a file message
  factory Message.file({
    required String filename,
    required String url,
    required String sender,
  }) {
    return Message(
      type: MessageType.file,
      content: filename,
      filename: filename,
      url: url,
      sender: sender,
    );
  }

  /// Create an image message
  factory Message.image({
    required String filename,
    required String url,
    required String sender,
  }) {
    return Message(
      type: MessageType.image,
      content: filename,
      filename: filename,
      url: url,
      sender: sender,
    );
  }

  /// Create a system message
  factory Message.system({required String content}) {
    return Message(type: MessageType.text, content: content, sender: 'System');
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'url': url,
    'sender': sender,
    'filename': filename,
    'timestamp': timestamp.toIso8601String(),
  };

  /// Create from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String?,
      type: MessageType.values.firstWhere((e) => e.name == json['type']),
      content: json['content'] as String,
      url: json['url'] as String?,
      sender: json['sender'] as String,
      filename: json['filename'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  bool get isMe => sender == 'Me';
  bool get isPC => sender == 'PC';
  bool get isSystem => sender == 'System';
}

class ConnectedScreen extends StatefulWidget {
  final String ip;
  final int port;
  final int httpPort;

  const ConnectedScreen({
    super.key,
    required this.ip,
    required this.port,
    required this.httpPort,
  });

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen>
    with WidgetsBindingObserver {
  late WebSocketChannel channel;
  List<Message> messages = [];
  final TextEditingController _textController = TextEditingController();
  StreamSubscription? _subscription;
  bool _isDisconnected = false;
  bool _isReconnecting = false;
  final ScrollController _scrollController = ScrollController();

  // Track if app is in foreground
  bool _isInForeground = true;

  // Unique device ID for reconnection support
  static String? _deviceId;

  // Track if this was an intentional disconnect
  bool _intentionalDisconnect = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeviceId();
    _loadSavedMessages();
    _connect();
  }

  Future<void> _initDeviceId() async {
    // Get or create a unique device ID for reconnection support
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
    }
    debugPrint('[DEBUG] Device ID: $_deviceId');
  }

  Future<void> _loadSavedMessages() async {
    final savedMessages = await MessageStorageService.loadMessages();
    if (savedMessages.isNotEmpty && mounted) {
      setState(() {
        messages = savedMessages;
      });
      // Scroll to bottom after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  Future<void> _saveMessages() async {
    await MessageStorageService.saveMessages(messages);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _connect() async {
    final wsUrl = Uri.parse('ws://${widget.ip}:${widget.port}');
    debugPrint('[DEBUG] ConnectedScreen: Connecting to $wsUrl');

    channel = WebSocketChannel.connect(wsUrl);

    _subscription = channel.stream.listen(
      (message) {
        debugPrint('[DEBUG] Received message: $message');
        try {
          final data = jsonDecode(message);
          debugPrint('[DEBUG] Parsed message type: ${data['type']}');
          _handleIncomingMessage(data);
        } catch (e) {
          debugPrint('[DEBUG] Failed to parse message: $e');
          // Fallback for plain text messages
          if (mounted && !_isDisconnected) {
            setState(() {
              messages.add(
                Message.text(content: message.toString(), sender: 'PC'),
              );
            });
            _saveMessages();
            _scrollToBottom();
          }
        }
      },
      onError: (error) {
        debugPrint('[DEBUG] WebSocket ERROR: $error');
        if (mounted && !_isDisconnected && !_intentionalDisconnect) {
          // Don't immediately disconnect - might be temporary network issue
          // Will attempt reconnect on app resume
          debugPrint(
            '[DEBUG] Connection error, will attempt reconnect on resume',
          );
        }
      },
      onDone: () {
        debugPrint('[DEBUG] WebSocket connection CLOSED');
        if (mounted && !_isDisconnected && !_intentionalDisconnect) {
          // Connection closed but not intentional - mark for potential reconnect
          debugPrint(
            '[DEBUG] Connection closed unexpectedly, will attempt reconnect on resume',
          );
        }
      },
    );

    // Send handshake to confirm connection with device ID and FCM token
    final prefs = await SharedPreferences.getInstance();
    final fcmToken = prefs.getString('fcm_token');
    _sendJson({
      'type': 'handshake',
      'device': 'Mobile',
      'deviceId': _deviceId,
      'fcmToken': fcmToken,
    });
    debugPrint(
      '[DEBUG] ConnectedScreen: Handshake sent with deviceId: $_deviceId, fcmToken: $fcmToken',
    );
  }

  /// Check if WebSocket is still connected
  bool _isConnected() {
    try {
      // Check if the channel is still active by checking ready future
      return !_isDisconnected && channel.closeCode == null;
    } catch (e) {
      return false;
    }
  }

  /// Attempt to reconnect to the server
  Future<void> _attemptReconnect() async {
    if (_isReconnecting || _intentionalDisconnect) return;

    _isReconnecting = true;
    debugPrint('[DEBUG] Attempting to reconnect...');

    try {
      // Close old subscription if exists
      await _subscription?.cancel();

      final wsUrl = Uri.parse('ws://${widget.ip}:${widget.port}');
      channel = WebSocketChannel.connect(wsUrl);

      _subscription = channel.stream.listen(
        (message) {
          debugPrint('[DEBUG] Received message on reconnect: $message');
          try {
            final data = jsonDecode(message);
            _handleIncomingMessage(data);
          } catch (e) {
            debugPrint('[DEBUG] Failed to parse message: $e');
            if (mounted && !_isDisconnected) {
              setState(() {
                messages.add(
                  Message.text(content: message.toString(), sender: 'PC'),
                );
              });
              _saveMessages();
              _scrollToBottom();
            }
          }
        },
        onError: (error) {
          debugPrint('[DEBUG] Reconnect WebSocket ERROR: $error');
          if (mounted && !_intentionalDisconnect) {
            _handleDisconnect('Connection error: $error');
          }
        },
        onDone: () {
          debugPrint('[DEBUG] Reconnect WebSocket CLOSED');
          if (mounted && !_intentionalDisconnect) {
            _handleDisconnect('Connection closed');
          }
        },
      );

      // Send reconnect message with device ID to retrieve queued messages
      _sendJson({'type': 'reconnect', 'deviceId': _deviceId});
      debugPrint('[DEBUG] Reconnect message sent');

      _isDisconnected = false;
      _isReconnecting = false;
    } catch (e) {
      debugPrint('[DEBUG] Reconnect failed: $e');
      _isReconnecting = false;
      if (mounted) {
        _handleDisconnect('Reconnection failed');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[DEBUG] App lifecycle changed: $state');
    setState(() {
      _isInForeground = state == AppLifecycleState.resumed;
    });

    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - check connection and reconnect if needed
      if (!_intentionalDisconnect && !_isConnected()) {
        debugPrint('[DEBUG] App resumed, attempting reconnect...');
        _attemptReconnect();
      }
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> data) {
    final String msgType = data['type'] ?? 'text';

    // Handle disconnect message from PC
    if (msgType == 'disconnect') {
      final reason = data['reason'] ?? 'PC disconnected';
      debugPrint('[DEBUG] Received disconnect message: $reason');
      _intentionalDisconnect = true; // PC initiated disconnect
      if (mounted && !_isDisconnected) {
        _handleDisconnect(reason);
      }
      return;
    }

    if (!mounted || _isDisconnected) return;

    switch (msgType) {
      case 'text':
        final content = data['content'] ?? '';
        setState(() {
          messages.add(Message.text(content: content, sender: 'PC'));
        });
        _saveMessages();
        if (!_isInForeground) {
          _showNotification("New Message", content, payload: "COPY:$content");
        }
        break;

      case 'handshake':
        // Connection established - no system message needed
        break;

      case 'file':
        final filename = data['filename'] ?? 'Unknown file';
        final url = data['url'] ?? '';
        setState(() {
          messages.add(
            Message.file(filename: filename, url: url, sender: 'PC'),
          );
        });
        _saveMessages();
        if (!_isInForeground) {
          _showNotification("File Received", filename, payload: url);
        }
        break;

      case 'image':
        final filename = data['filename'] ?? 'Unknown image';
        final url = data['url'] ?? '';
        setState(() {
          messages.add(
            Message.image(filename: filename, url: url, sender: 'PC'),
          );
        });
        _saveMessages();
        if (!_isInForeground) {
          _showNotification("Image Received", filename, payload: url);
        }
        break;

      case 'clipboard':
        final clipboardContent = data['content'] ?? '';
        _showClipboardDialog(clipboardContent);
        break;

      // Legacy support for file_offer
      case 'file_offer':
        final filename = data['filename'] ?? 'Unknown file';
        final url = data['url'] ?? '';
        setState(() {
          messages.add(
            Message.file(filename: filename, url: url, sender: 'PC'),
          );
        });
        _saveMessages();
        if (!_isInForeground) {
          _showNotification("File Received", filename, payload: url);
        }
        _showFileOfferDialog(filename, url);
        break;
    }

    _scrollToBottom();
  }

  void _showClipboardDialog(String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clipboard Sync'),
        content: Text('Received from PC: $content'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ignore'),
          ),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to mobile clipboard')),
              );
            },
            child: const Text('Copy to Mobile'),
          ),
        ],
      ),
    );
  }

  void _handleDisconnect(String reason) {
    if (_isDisconnected) return; // Prevent multiple calls
    _isDisconnected = true;

    // Close WebSocket
    channel.sink.close();

    // Navigate to home screen with message
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
      // Show snackbar with disconnect reason
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Disconnected: $reason'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleUserDisconnect() {
    if (_isDisconnected) return;
    _isDisconnected = true;
    _intentionalDisconnect = true;

    // Send disconnect message to PC
    _sendJson({'type': 'disconnect', 'reason': 'user_initiated'});
    debugPrint('[DEBUG] Sent disconnect message to PC');

    // Close WebSocket
    channel.sink.close();

    // Navigate to home screen
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _showNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'fast_share_channel',
          'Fast Share Notifications',
          channelDescription: 'Notifications for Fast Share messages and files',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  void _sendJson(Map<String, dynamic> data) {
    if (!_isDisconnected) {
      channel.sink.add(jsonEncode(data));
    }
  }

  void _sendText() {
    if (_textController.text.isNotEmpty && !_isDisconnected) {
      final text = _textController.text;
      _sendJson({'type': 'text', 'content': text});
      setState(() {
        messages.add(Message.text(content: text, sender: 'Me'));
      });
      _saveMessages();
      _textController.clear();
      _scrollToBottom();
    }
  }

  void _showFileOfferDialog(String filename, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("File Received"),
        content: Text(
          "PC sent you a file: $filename\nDo you want to download it?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openUrl(url);
            },
            child: const Text("Download"),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // URL launch failed - silently ignore or could log for debugging
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_isDisconnected) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      String filename = result.files.single.name;

      // Determine if it's an image
      final isImage = RegExp(
        r'\.(jpg|jpeg|png|gif|webp|bmp)$',
        caseSensitive: false,
      ).hasMatch(filename);

      // Create the file URL that will be available after upload
      final fileUrl =
          'http://${widget.ip}:${widget.httpPort}/files/${Uri.encodeComponent(filename)}';

      // Add the message immediately (optimistic UI update)
      final message = isImage
          ? Message.image(filename: filename, url: fileUrl, sender: 'Me')
          : Message.file(filename: filename, url: fileUrl, sender: 'Me');

      if (mounted && !_isDisconnected) {
        setState(() {
          messages.add(message);
        });
        _saveMessages();
        _scrollToBottom();
      }

      try {
        var request = http.StreamedRequest(
          'POST',
          Uri.parse('http://${widget.ip}:${widget.httpPort}/upload'),
        );
        request.headers['x-filename'] = filename;
        request.contentLength = await file.length();

        request.sink.addStream(file.openRead());

        final response = await request.send();

        if (mounted && !_isDisconnected) {
          if (response.statusCode != 200) {
            // Remove the failed message silently
            setState(() {
              messages.removeWhere((m) => m.id == message.id);
            });
            _saveMessages();
          }
        }
      } catch (e) {
        if (mounted && !_isDisconnected) {
          // Remove the failed message silently
          setState(() {
            messages.removeWhere((m) => m.id == message.id);
          });
          _saveMessages();
        }
      }
    }
  }

  void _deleteMessage(Message message) {
    setState(() {
      messages.removeWhere((m) => m.id == message.id);
    });
    _saveMessages();
  }

  void _clearAllMessages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear History"),
        content: const Text("Are you sure you want to clear all messages?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                messages.clear();
              });
              MessageStorageService.clearMessages();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Clear", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    channel.sink.close();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connected to ${widget.ip}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleUserDisconnect,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _isDisconnected ? null : _pickAndSendFile,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear History',
            onPressed: _clearAllMessages,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Disconnect',
            onPressed: _handleUserDisconnect,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final Message msg = messages[index];
                final Message? previousMsg = index > 0
                    ? messages[index - 1]
                    : null;
                return MessageBubble(
                  message: msg,
                  previousMessage: previousMsg,
                  onTap: () {
                    if (msg.url != null) {
                      _openUrl(msg.url!);
                    }
                  },
                  onLongPress: () {
                    _showMessageOptions(msg);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isDisconnected ? null : _sendText,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == MessageType.text) ...[
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
              const Divider(height: 1),
            ],
            if (message.url != null) ...[
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(context);
                  _openUrl(message.url!);
                },
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Format time for message timestamp
String _formatMessageTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Format date for day separator
String _formatDaySeparator(DateTime date) {
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);

  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'Today';
  } else if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Yesterday';
  } else {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Message bubble widget that displays different UI based on message type
class MessageBubble extends StatelessWidget {
  final Message message;
  final Message? previousMessage;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    this.previousMessage,
    this.onTap,
    this.onLongPress,
  });

  bool get _showDaySeparator {
    if (previousMessage == null) return true;
    return message.timestamp.toDateString() !=
        previousMessage!.timestamp.toDateString();
  }

  bool get _showTimestamp {
    if (previousMessage == null) return true;
    // Show timestamp if more than 5 minutes gap or different sender
    final diff = message.timestamp.difference(previousMessage!.timestamp);
    return diff.inMinutes > 5 || message.sender != previousMessage!.sender;
  }

  @override
  Widget build(BuildContext context) {
    // System messages are centered
    if (message.isSystem) {
      return Column(
        children: [
          if (_showDaySeparator) _buildDaySeparator(message.timestamp),
          _buildSystemBubble(),
        ],
      );
    }

    // Align based on sender
    final isMe = message.isMe;
    return Column(
      children: [
        if (_showDaySeparator) _buildDaySeparator(message.timestamp),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Sender label
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.sender,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                // Message content based on type
                _buildMessageContent(context, isMe),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaySeparator(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDaySeparator(date),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildSystemBubble() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, bool isMe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        InkWell(
          onLongPress: onLongPress,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: _buildBubbleContent(context, isMe),
        ),
        if (_showTimestamp)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Text(
              _formatMessageTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.blue[200] : Colors.grey[500],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBubbleContent(BuildContext context, bool isMe) {
    switch (message.type) {
      case MessageType.text:
        return _buildTextBubble(context, isMe);
      case MessageType.file:
        return _buildFileBubble(context, isMe);
      case MessageType.image:
        return _buildImageBubble(context, isMe);
    }
  }

  Widget _buildTextBubble(BuildContext context, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[400] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Linkify(
        text: message.content,
        style: TextStyle(
          fontSize: 16,
          color: isMe ? Colors.white : Colors.black87,
        ),
        linkStyle: TextStyle(
          fontSize: 16,
          color: isMe ? Colors.white : Colors.blue,
          decoration: TextDecoration.underline,
        ),
        onOpen: (link) async {
          final Uri url = Uri.parse(link.url);
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            // URL launch failed - silently ignore
          }
        },
      ),
    );
  }

  Widget _buildFileBubble(BuildContext context, bool isMe) {
    final iconData = _getFileIcon(message.filename ?? '');
    final iconColor = _getFileIconColor(message.filename ?? '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? Colors.blue[200]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, color: iconColor, size: 32),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.filename ?? 'Unknown file',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to download',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBubble(BuildContext context, bool isMe) {
    final String? url = message.url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, size: 40, color: Colors.grey),
                      SizedBox(height: 4),
                      Text(
                        'Failed to load',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                color: Colors.grey[200],
                child: const Icon(Icons.image, size: 40, color: Colors.grey),
              ),
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Icons.video_file;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.orange;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}

/// Extension for DateTime to compare dates
extension DateTimeExtension on DateTime {
  String toDateString() {
    return '$year-$month-$day';
  }
}
