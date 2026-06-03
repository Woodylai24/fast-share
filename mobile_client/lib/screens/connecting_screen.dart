import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:fast_share_mobile/models/connection_entry.dart';
import 'package:fast_share_mobile/services/connection_history.dart';
import 'package:fast_share_mobile/screens/home_screen.dart';
import 'package:fast_share_mobile/screens/chat_screen.dart';

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
