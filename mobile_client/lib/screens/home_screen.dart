import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fast_share_mobile/screens/chat_screen.dart';
import 'package:fast_share_mobile/screens/settings_screen.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/services/notifications.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';
import 'package:fast_share_mobile/widgets/qr_scanner.dart';

/// First-launch pairing screen (shown only when no PC is paired yet).
///
/// On every subsequent launch the app opens straight to ChatScreen
/// (see main.dart), so this screen only appears:
///  - on first launch before any pairing, or
///  - after the user unpairs ("Change PC") from ChatScreen.
class HomeScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const HomeScreen({super.key, required this.themeNotifier});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissions();
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

  /// Parse "ip", "ip:port", or "ip:port" with an http port hint, save it as
  /// the active pairing, and open ChatScreen (which connects on its own).
  Future<void> _handleConnect() async {
    final text = _ipController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    String ip;
    int port = 8080; // default WebSocket port
    int httpPort = 8081; // default HTTP port

    if (text.contains(':')) {
      final parts = text.split(':');
      ip = parts[0];
      port = int.tryParse(parts[1]) ?? 8080;
    } else {
      ip = text;
    }

    await SettingsService.setLastConnection(ip, port, httpPort);

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => ConnectedScreen(
          ip: ip,
          port: port,
          httpPort: httpPort,
          themeNotifier: widget.themeNotifier,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _openQrScanner() async {
    if (await Permission.camera.request().isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ScannerScreen(themeNotifier: widget.themeNotifier),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission required')),
      );
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fast Share'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SettingsScreen(themeNotifier: widget.themeNotifier),
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
              const SizedBox(height: 24),
              const Text(
                'Connect to your PC',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan the QR code shown in the Fast Share desktop app, '
                'or enter your PC\'s IP address manually. Both devices must '
                'be on the same Wi-Fi network.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              // Primary: QR scanner
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Code'),
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

              // Secondary: manual IP entry
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'IP Address',
                  hintText: 'e.g. 192.168.1.10:8080',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _handleConnect(),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 16),
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
            ],
          ),
        ),
      ),
    );
  }
}
