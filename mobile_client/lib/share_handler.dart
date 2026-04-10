import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Utility to handle incoming shares from Android OS (PROCESS_TEXT, SEND, SEND_MULTIPLE).
/// Routes shared content through the existing ConnectedScreen's WebSocket.
class ShareHandler {
  static const MethodChannel _channel = MethodChannel('fast_share/share_receiver');

  static void Function(Map<String, dynamic>)? _sendCallback;
  static void Function(Map<String, String>)? _localMessageCallback;

  static Map<String, String>? _pendingShare;
  static BuildContext? _context;

  /// Set up the MethodChannel listener. Call once.
  static void setupListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived') {
        final Map args = call.arguments as Map;
        _pendingShare = {
          'type': args['type'] as String,
          'data': args['data'] as String,
          'mimeType': args['mimeType'] as String? ?? 'text/plain',
        };
        _processPendingShare();
      }
    });
  }

  static void setContext(BuildContext context) {
    _context = context;
    if (_pendingShare != null) {
      _processPendingShare();
    }
  }

  static void registerSendCallback(void Function(Map<String, dynamic>) callback) {
    _sendCallback = callback;
  }

  static void registerLocalMessageCallback(void Function(Map<String, String>) callback) {
    _localMessageCallback = callback;
  }

  static void unregisterSendCallback() {
    _sendCallback = null;
    _localMessageCallback = null;
  }

  static Future<void> _processPendingShare() async {
    if (_pendingShare == null) return;
    final share = _pendingShare!;
    _pendingShare = null;

    debugPrint('[DEBUG] ShareHandler: processing share type=${share['type']}');

    try {
      if (_sendCallback == null) {
        debugPrint('[DEBUG] ShareHandler: no callback registered');
        return;
      }

      final type = share['type']!;
      final data = share['data']!;

      if (type == 'text') {
        _sendCallback!({'type': 'text', 'content': data});
      } else if (type == 'file' || type == 'files') {
        final prefs = await SharedPreferences.getInstance();
        final lastIp = prefs.getString('last_connected_ip');
        final lastHttpPort = prefs.getInt('last_connected_http_port') ?? 8081;

        debugPrint('[DEBUG] ShareHandler: lastIp=$lastIp, lastHttpPort=$lastHttpPort');

        if (lastIp == null) {
          debugPrint('[DEBUG] ShareHandler: no saved connection');
          return;
        }

        final uris = type == 'files' ? data.split(',') : [data];
        final sentFiles = <Map<String, String>>[];

        for (final uriString in uris) {
          try {
            debugPrint('[DEBUG] ShareHandler: resolving URI $uriString');
            final filePath = await _resolveContentUri(uriString);
            debugPrint('[DEBUG] ShareHandler: resolved to $filePath');
            if (filePath != null) {
              debugPrint('[DEBUG] ShareHandler: starting upload to $lastIp:$lastHttpPort');
              await _uploadFile(lastIp, lastHttpPort, filePath);
              debugPrint('[DEBUG] ShareHandler: upload done');
              final filename = filePath.split('/').last;
              sentFiles.add({
                'filename': filename,
                'url': 'http://$lastIp:$lastHttpPort/files/$filename',
              });
            }
          } catch (e) {
            debugPrint('[DEBUG] ShareHandler file error: $e');
          }
        }

        // Trigger local message callback for each sent file
        if (_localMessageCallback != null) {
          for (final fileInfo in sentFiles) {
            _localMessageCallback!(fileInfo);
          }
        }
      }
    } catch (e) {
      debugPrint('[DEBUG] ShareHandler error: $e');
    }
  }

  static Future<String?> _resolveContentUri(String uriString) async {
    const channel = MethodChannel('fast_share/file_helper');
    try {
      final filePath = await channel.invokeMethod('resolveContentUri', {'uri': uriString});
      return filePath as String?;
    } catch (e) {
      debugPrint('[DEBUG] ShareHandler: resolveContentUri failed: $e');
      final uri = Uri.parse(uriString);
      if (uri.scheme == 'file') return uri.path;
      return null;
    }
  }

  static Future<void> _uploadFile(String ip, int httpPort, String filePath) async {
    debugPrint('[DEBUG] ShareHandler._uploadFile: $filePath');
    final file = File(filePath);
    final exists = await file.exists();
    debugPrint('[DEBUG] ShareHandler._uploadFile: exists=$exists, size=${exists ? await file.length() : 0}');

    final filename = filePath.split('/').last;
    final uri = Uri.parse('http://$ip:$httpPort/upload');

    final bytes = await file.readAsBytes();
    debugPrint('[DEBUG] ShareHandler._uploadFile: read ${bytes.length} bytes');

    final request = http.Request('POST', uri);
    request.headers['x-filename'] = filename;
    request.headers['Content-Type'] = 'application/octet-stream';
    request.bodyBytes = bytes;

    debugPrint('[DEBUG] ShareHandler._uploadFile: sending request...');
    final response = await request.send();
    debugPrint('[DEBUG] ShareHandler._uploadFile: response status=${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.statusCode}');
    }
  }
}
