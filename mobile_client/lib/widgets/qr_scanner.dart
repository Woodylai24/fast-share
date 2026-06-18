import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fast_share_mobile/screens/chat_screen.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';

class ScannerScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const ScannerScreen({super.key, required this.themeNotifier});

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
                  final ip = data['ip'] as String;
                  final port = (data['port'] as num).toInt();
                  final httpPort = (data['httpPort'] as num?)?.toInt() ?? 8081;

                  setState(() {
                    hasScanned = true;
                  });

                  // Save the pairing so the next launch opens straight to
                  // ChatScreen, then go straight to ChatScreen (it opens its
                  // own WebSocket — no separate ConnectingScreen needed).
                  SettingsService.setLastConnection(ip, port, httpPort);
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
