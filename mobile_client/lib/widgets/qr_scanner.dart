import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fast_share_mobile/screens/connecting_screen.dart';
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
                        themeNotifier: widget.themeNotifier,
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
