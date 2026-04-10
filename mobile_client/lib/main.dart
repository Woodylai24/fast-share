import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'share_handler.dart';
import 'crypto_service.dart';
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
                  return;
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

      // Listen for messages
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_connected_ip', widget.ip);
      await prefs.setInt('last_connected_port', widget.port);
      await prefs.setInt('last_connected_http_port', widget.httpPort);
      debugPrint(
        '[DEBUG] Connection saved to history: ${entry.ip}:${entry.port}, network: ${entry.networkName}',
      );
    } catch (e) {
      debugPrint('[DEBUG] Failed to save connection to history: $e');
    }
  }

  @override
  void dispose() {
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

  // Track last clipboard for mobile-to-PC sync
  String? _lastClipboardText;
  String? _lastReceivedClipboard; // To prevent loopback
  Timer? _clipboardPollTimer;

  // Unique device ID for reconnection support
  static String? _deviceId;

  // Track if this was an intentional disconnect
  bool _intentionalDisconnect = false;

  // E2EE crypto service
  final CryptoService _crypto = CryptoService();
  bool _keyExchangeComplete = false;
  Timer? _keyExchangeTimeout;

  // File chunk reassembly state
  _IncomingFileTransfer? _incomingFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeviceId();
    _loadSavedMessages();
    _connect();
    _startClipboardPolling();
    _setupShareHandler();
  }

  Future<void> _initDeviceId() async {
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

    // Initialize crypto for this connection
    await _crypto.init();
    _keyExchangeComplete = false;
    debugPrint('[DEBUG] CryptoService initialized with new ephemeral key pair');

    channel = WebSocketChannel.connect(wsUrl);

    _subscription = channel.stream.listen(
      (message) {
        debugPrint('[DEBUG] Received message: $message');
        try {
          final data = jsonDecode(message);
          debugPrint('[DEBUG] Parsed message type: ${data['type']}');
          _handleRawMessage(data);
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
        debugPrint('[DEBUG] WebSocket ERROR: $error');
        if (mounted && !_isDisconnected && !_intentionalDisconnect) {
          debugPrint(
            '[DEBUG] Connection error, will attempt reconnect on resume',
          );
        }
      },
      onDone: () {
        debugPrint('[DEBUG] WebSocket connection CLOSED');
        if (mounted && !_isDisconnected && !_intentionalDisconnect) {
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

  /// Handle raw messages from WebSocket (before decryption)
  void _handleRawMessage(Map<String, dynamic> data) {
    final String msgType = data['type'] ?? '';

    // Handle key-exchange from server
    if (msgType == 'key-exchange') {
      debugPrint('[DEBUG] Received key-exchange from server');
      _handleKeyExchange(data['publicKey'] as String);
      return;
    }

    // Handle handshake from server
    if (msgType == 'handshake') {
      debugPrint('[DEBUG] Received handshake from server');
      // Key exchange will follow
      return;
    }

    // Handle encrypted messages
    if (msgType == 'encrypted') {
      if (!_keyExchangeComplete) {
        debugPrint('[DEBUG] Received encrypted message before key exchange — dropping');
        return;
      }
      _handleEncryptedMessage(data);
      return;
    }

    // Handle disconnect
    if (msgType == 'disconnect') {
      final reason = data['reason'] ?? 'PC disconnected';
      debugPrint('[DEBUG] Received disconnect message: $reason');
      _intentionalDisconnect = true;
      if (mounted && !_isDisconnected) {
        _handleDisconnect(reason);
      }
      return;
    }

    // Legacy plaintext messages (fallback)
    _handleIncomingMessage(data);
  }

  /// Handle key exchange — compute shared secret
  Future<void> _handleKeyExchange(String serverPublicKey) async {
    try {
      await _crypto.computeSharedSecret(serverPublicKey);
      _keyExchangeComplete = true;
      _keyExchangeTimeout?.cancel();

      // Send our public key back to server
      final ourPublicKey = await _crypto.getPublicKeyBase64();
      _sendJson({'type': 'key-exchange', 'publicKey': ourPublicKey});
      debugPrint('[DEBUG] Key exchange complete — encrypted channel established');
    } catch (e) {
      debugPrint('[DEBUG] Key exchange failed: $e');
    }
  }

  /// Handle an encrypted message — decrypt and process
  Future<void> _handleEncryptedMessage(Map<String, dynamic> wrapper) async {
    final decrypted = await _crypto.decrypt({
      'nonce': wrapper['nonce'] as String,
      'payload': wrapper['payload'] as String,
      'tag': wrapper['tag'] as String,
    });

    if (decrypted == null) {
      debugPrint('[DEBUG] Decryption failed — dropping message');
      return;
    }

    debugPrint('[DEBUG] Decrypted inner message type: ${decrypted['type']}');
    _handleIncomingMessage(decrypted);
  }

  /// Check if WebSocket is still connected
  bool _isConnected() {
    try {
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
      await _subscription?.cancel();

      // Re-initialize crypto for new ephemeral keys
      await _crypto.init();
      _keyExchangeComplete = false;

      final wsUrl = Uri.parse('ws://${widget.ip}:${widget.port}');
      channel = WebSocketChannel.connect(wsUrl);

      _subscription = channel.stream.listen(
        (message) {
          debugPrint('[DEBUG] Received message on reconnect: $message');
          try {
            final data = jsonDecode(message);
            _handleRawMessage(data);
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

      // Send reconnect message with device ID
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
      if (!_intentionalDisconnect && !_isConnected()) {
        debugPrint('[DEBUG] App resumed, attempting reconnect...');
        _attemptReconnect();
      }
      _checkAndSendClipboard();
    } else if (state == AppLifecycleState.paused) {
      _saveCurrentClipboard();
    }
  }

  /// Process a decrypted (or plaintext legacy) message
  void _handleIncomingMessage(Map<String, dynamic> data) {
    final String msgType = data['type'] ?? 'text';

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
        if (!_isInForeground) {
          _showNotification("Clipboard Sync", clipboardContent.length > 50 ? clipboardContent.substring(0, 50) + '...' : clipboardContent, payload: "COPY:$clipboardContent");
        }
        _showClipboardDialog(clipboardContent);
        break;

      case 'file-start':
        _handleFileStart(data);
        break;

      case 'file-chunk':
        _handleFileChunk(data);
        break;

      case 'file-end':
        _handleFileEnd(data);
        break;

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

  // --- Encrypted file transfer handling ---

  void _handleFileStart(Map<String, dynamic> data) {
    debugPrint('[DEBUG] File transfer starting: ${data['filename']} (${data['fileSize']} bytes)');
    _incomingFile?._cleanup();
    _incomingFile = _IncomingFileTransfer(
      filename: data['filename'] as String,
      fileSize: data['fileSize'] as int,
      mimeType: data['mimeType'] as String? ?? 'application/octet-stream',
    );
  }

  void _handleFileChunk(Map<String, dynamic> data) {
    if (_incomingFile == null) {
      debugPrint('[DEBUG] Received file-chunk without file-start — dropping');
      return;
    }
    final chunkData = base64Decode(data['data'] as String);
    _incomingFile!.chunks.add(chunkData);
    _incomingFile!.receivedBytes += chunkData.length;
    _incomingFile!._resetTimer();
  }

  Future<void> _handleFileEnd(Map<String, dynamic> data) async {
    if (_incomingFile == null) {
      debugPrint('[DEBUG] Received file-end without file-start — ignoring');
      return;
    }

    final transfer = _incomingFile!;
    _incomingFile = null;
    transfer._cancelTimer();

    // Assemble and verify checksum
    final assembled = <int>[];
    for (final chunk in transfer.chunks) {
      assembled.addAll(chunk);
    }

    final checksum = await CryptoService.sha256(assembled);
    if (checksum != data['checksum']) {
      debugPrint('[DEBUG] File checksum mismatch: expected ${data['checksum']}, got $checksum');
      return;
    }

    // Determine file type for message display
    final filename = transfer.filename;
    final isImage = RegExp(
      r'\.(jpg|jpeg|png|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(filename);

    // Save file locally on device (no need to fetch from PC's HTTP server)
    String fileUrl;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fastShareDir = Directory('${appDir.path}/FastShare');
      if (!await fastShareDir.exists()) {
        await fastShareDir.create(recursive: true);
      }
      final localFile = File('${fastShareDir.path}/$filename');
      await localFile.writeAsBytes(assembled);
      fileUrl = 'file://${localFile.path}';
      debugPrint('[DEBUG] File saved locally: ${localFile.path}');
    } catch (e) {
      debugPrint('[DEBUG] Failed to save file locally: $e');
      // Fallback to HTTP URL
      fileUrl =
          'http://${widget.ip}:${widget.httpPort}/files/${Uri.encodeComponent(filename)}';
    }

    if (mounted && !_isDisconnected) {
      setState(() {
        if (isImage) {
          messages.add(Message.image(filename: filename, url: fileUrl, sender: 'PC'));
        } else {
          messages.add(Message.file(filename: filename, url: fileUrl, sender: 'PC'));
        }
      });
      _saveMessages();
      _scrollToBottom();

      if (!_isInForeground) {
        _showNotification("File Received", filename, payload: fileUrl);
      }
    }

    debugPrint('[DEBUG] File transfer complete: $filename (${transfer.receivedBytes} bytes)');
  }

  void _showClipboardDialog(String content) {
    if (!mounted) return;
    _lastReceivedClipboard = content;
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
    if (_isDisconnected) return;
    _isDisconnected = true;

    _incomingFile?._cleanup();
    _incomingFile = null;
    _keyExchangeTimeout?.cancel();

    channel.sink.close();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
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

    _incomingFile?._cleanup();
    _incomingFile = null;
    _keyExchangeTimeout?.cancel();

    _sendJson({'type': 'disconnect', 'reason': 'user_initiated'});
    debugPrint('[DEBUG] Sent disconnect message to PC');

    channel.sink.close();

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

  /// Send JSON to server — encrypts if key exchange is complete.
  void _sendJson(Map<String, dynamic> data) {
    if (_isDisconnected) return;

    final type = data['type'] as String?;

    // Unencrypted types are sent as plaintext
    if (type != null && isUnencryptedType(type)) {
      channel.sink.add(jsonEncode(data));
      return;
    }

    // Encrypt if key exchange is complete
    if (_keyExchangeComplete && _crypto.isReady) {
      _sendEncrypted(data);
    } else {
      // Fallback to plaintext if key exchange not yet complete
      channel.sink.add(jsonEncode(data));
    }
  }

  /// Encrypt and send a message
  void _sendEncrypted(Map<String, dynamic> data) async {
    try {
      final encrypted = await _crypto.encrypt(data);
      channel.sink.add(jsonEncode({
        'type': 'encrypted',
        ...encrypted,
      }));
    } catch (e) {
      debugPrint('[DEBUG] Failed to encrypt message, sending plaintext: $e');
      channel.sink.add(jsonEncode(data));
    }
  }

  /// Send a file via encrypted chunked WebSocket transfer.
  Future<void> _sendFileViaWs(String filePath, String filename) async {
    if (!_keyExchangeComplete || !_crypto.isReady) {
      debugPrint('[DEBUG] Key exchange not complete, falling back to HTTP upload');
      await _uploadFileViaHttp(filePath, filename);
      return;
    }

    try {
      final file = File(filePath);
      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;
      final mimeType = _getMimeType(filename);
      final checksum = await CryptoService.sha256(fileBytes);

      // Send file-start
      _sendEncrypted({
        'type': 'file-start',
        'filename': filename,
        'fileSize': fileSize,
        'mimeType': mimeType,
      });

      // Send file-chunks (64KB)
      const chunkSize = 64 * 1024;
      int offset = 0;
      int seq = 0;
      while (offset < fileSize) {
        final end = (offset + chunkSize > fileSize) ? fileSize : offset + chunkSize;
        final chunk = fileBytes.sublist(offset, end);
        _sendEncrypted({
          'type': 'file-chunk',
          'seq': seq,
          'data': base64Encode(chunk),
        });
        offset = end;
        seq++;
      }

      // Send file-end
      _sendEncrypted({
        'type': 'file-end',
        'filename': filename,
        'checksum': checksum,
      });

      debugPrint('[DEBUG] File sent via encrypted WS: $filename ($fileSize bytes, $seq chunks)');
    } catch (e) {
      debugPrint('[DEBUG] Failed to send file via WS, falling back to HTTP: $e');
      await _uploadFileViaHttp(filePath, filename);
    }
  }

  /// Legacy HTTP upload fallback
  Future<void> _uploadFileViaHttp(String filePath, String filename) async {
    try {
      var request = http.StreamedRequest(
        'POST',
        Uri.parse('http://${widget.ip}:${widget.httpPort}/upload'),
      );
      request.headers['x-filename'] = filename;
      final file = File(filePath);
      request.contentLength = await file.length();
      request.sink.addStream(file.openRead());

      final response = await request.send();
      debugPrint('[DEBUG] HTTP upload response: ${response.statusCode}');
    } catch (e) {
      debugPrint('[DEBUG] HTTP upload failed: $e');
    }
  }

  String _getMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    const mimeMap = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'bmp': 'image/bmp', 'webp': 'image/webp',
      'svg': 'image/svg+xml', 'pdf': 'application/pdf', 'zip': 'application/zip',
      'txt': 'text/plain', 'json': 'application/json',
      'mp4': 'video/mp4', 'mp3': 'audio/mpeg',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  void _setupShareHandler() {
    ShareHandler.setupListener();
    ShareHandler.setContext(context);

    // Register the encrypted send callback
    ShareHandler.registerSendCallback((data) {
      _sendJson(data);
      if (data['type'] == 'text' && data['content'] != null) {
        setState(() {
          messages.add(Message.text(content: data['content'] as String, sender: 'Me'));
        });
        _saveMessages();
        _scrollToBottom();
      }
    });

    ShareHandler.registerLocalMessageCallback((fileInfo) {
      final filename = fileInfo['filename'] ?? 'Unknown';
      final url = fileInfo['url'] ?? '';
      final isImage = filename.toLowerCase().endsWith('.jpg') ||
          filename.toLowerCase().endsWith('.jpeg') ||
          filename.toLowerCase().endsWith('.png') ||
          filename.toLowerCase().endsWith('.gif') ||
          filename.toLowerCase().endsWith('.webp') ||
          filename.toLowerCase().endsWith('.bmp');
      setState(() {
        if (isImage) {
          messages.add(Message.image(filename: filename, url: url, sender: 'Me'));
        } else {
          messages.add(Message.file(filename: filename, url: url, sender: 'Me'));
        }
      });
      _saveMessages();
      _scrollToBottom();
    });
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

  // --- Mobile-to-PC Clipboard Sync ---
  void _startClipboardPolling() {
    _clipboardPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isInForeground && !_isDisconnected) {
        _checkAndSendClipboard();
      }
    });
  }

  void _saveCurrentClipboard() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text != null) {
        _lastClipboardText = data!.text;
        debugPrint('[DEBUG] Saved clipboard state: ${_lastClipboardText?.substring(0, (_lastClipboardText!.length > 30 ? 30 : _lastClipboardText!.length))}...');
      }
    });
  }

  void _checkAndSendClipboard() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text == null) return;
      final currentClipboard = data!.text!;
      if (currentClipboard != _lastClipboardText && currentClipboard != _lastReceivedClipboard) {
        debugPrint('[DEBUG] Clipboard changed while in background, sending to PC');
        _sendJson({'type': 'clipboard', 'content': currentClipboard});
        _lastClipboardText = currentClipboard;
      }
    });
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
      // URL launch failed
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_isDisconnected) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      String filename = result.files.single.name;

      final isImage = RegExp(
        r'\.(jpg|jpeg|png|gif|webp|bmp)$',
        caseSensitive: false,
      ).hasMatch(filename);

      // Create the file URL (for display, actual transfer is via WS)
      final fileUrl =
          'http://${widget.ip}:${widget.httpPort}/files/${Uri.encodeComponent(filename)}';

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

      // Send file via encrypted WS (or HTTP fallback)
      try {
        await _sendFileViaWs(file.path, filename);
      } catch (e) {
        debugPrint('[DEBUG] File send failed: $e');
        if (mounted && !_isDisconnected) {
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
    _clipboardPollTimer?.cancel();
    _keyExchangeTimeout?.cancel();
    _incomingFile?._cleanup();
    ShareHandler.unregisterSendCallback();
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

/// Incoming file transfer state for reassembly
class _IncomingFileTransfer {
  final String filename;
  final int fileSize;
  final String mimeType;
  final List<Uint8List> chunks = [];
  int receivedBytes = 0;
  Timer? _timer;

  _IncomingFileTransfer({
    required this.filename,
    required this.fileSize,
    required this.mimeType,
  }) {
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 30), () {
      debugPrint('[DEBUG] File chunk reassembly timeout for $filename');
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
  }

  void _cleanup() {
    _cancelTimer();
    chunks.clear();
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
    return true;
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
            // URL launch failed
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

    // Handle local file:// URLs vs remote http:// URLs
    final bool isLocalFile = url != null && url.startsWith('file://');

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
        child: url != null
            ? isLocalFile
                ? Image.file(
                    File(url.replaceFirst('file://', '')),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
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
                : CachedNetworkImage(
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
