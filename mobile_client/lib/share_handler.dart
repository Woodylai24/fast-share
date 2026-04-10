import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_service.dart';

/// Utility to handle incoming shares from Android OS (PROCESS_TEXT, SEND, SEND_MULTIPLE).
/// Routes shared content through the existing ConnectedScreen's WebSocket.
class ShareHandler {
  static const MethodChannel _channel = MethodChannel('fast_share/share_receiver');

  /// Maximum chunk size in bytes (64 KB) before base64 encoding.
  static const int _chunkSize = 64 * 1024;

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

        final uris = type == 'files' ? data.split(',') : [data];
        final sentFiles = <Map<String, String>>[];

        for (final uriString in uris) {
          try {
            debugPrint('[DEBUG] ShareHandler: resolving URI $uriString');
            final filePath = await _resolveContentUri(uriString);
            debugPrint('[DEBUG] ShareHandler: resolved to $filePath');
            if (filePath != null) {
              final filename = filePath.split('/').last;

              // Send via encrypted WebSocket chunks if callback is available
              if (_sendCallback != null) {
                debugPrint('[DEBUG] ShareHandler: sending file via encrypted WS chunks');
                await _sendFileChunks(filePath, filename, share['mimeType'] ?? 'application/octet-stream');
              } else if (lastIp != null) {
                // Fallback to HTTP upload
                debugPrint('[DEBUG] ShareHandler: falling back to HTTP upload');
                await _uploadFile(lastIp, lastHttpPort, filePath);
              } else {
                debugPrint('[DEBUG] ShareHandler: no connection available');
                continue;
              }

              sentFiles.add({
                'filename': filename,
                'url': 'file://$filePath',
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

  /// Send a file via encrypted WebSocket in 64KB chunks.
  ///
  /// Sends three message types through `_sendCallback`:
  /// - `file-start`: metadata (filename, fileSize, mimeType)
  /// - `file-chunk`: sequential base64-encoded chunks (64KB each)
  /// - `file-end`: completion with SHA-256 checksum
  ///
  /// Encryption is handled upstream by ConnectedScreen.
  static Future<void> _sendFileChunks(
    String filePath,
    String filename,
    String mimeType,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final fileSize = bytes.length;
    final checksum = await CryptoService.sha256(bytes);

    debugPrint('[DEBUG] ShareHandler._sendFileChunks: $filename ($fileSize bytes, checksum=$checksum)');

    // 1. Send file-start
    _sendCallback!({
      'type': 'file-start',
      'filename': filename,
      'fileSize': fileSize,
      'mimeType': mimeType,
    });

    // 2. Send file-chunk messages (64KB chunks, base64 encoded)
    int offset = 0;
    int seq = 0;
    while (offset < bytes.length) {
      final end = (offset + _chunkSize > bytes.length) ? bytes.length : offset + _chunkSize;
      final chunk = bytes.sublist(offset, end);
      final base64Chunk = base64Encode(chunk);

      _sendCallback!({
        'type': 'file-chunk',
        'seq': seq,
        'data': base64Chunk,
      });

      offset = end;
      seq++;
    }

    debugPrint('[DEBUG] ShareHandler._sendFileChunks: sent $seq chunks');

    // 3. Send file-end with checksum
    _sendCallback!({
      'type': 'file-end',
      'filename': filename,
      'checksum': checksum,
    });

    debugPrint('[DEBUG] ShareHandler._sendFileChunks: complete');
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

  /// Legacy HTTP upload fallback (kept for backwards compatibility).
  static Future<void> _uploadFile(String ip, int httpPort, String filePath) async {
    debugPrint('[DEBUG] ShareHandler._uploadFile: $filePath');
    final file = File(filePath);
    final exists = await file.exists();
    debugPrint('[DEBUG] ShareHandler._uploadFile: exists=$exists, size=${exists ? await file.length() : 0}');

    final filename = filePath.split('/').last;
    final uri = Uri.parse('http://$ip:$httpPort/upload');

    final bytes = await file.readAsBytes();
    debugPrint('[DEBUG] ShareHandler._uploadFile: read ${bytes.length} bytes');

    final request = await HttpClient().postUrl(uri);
    request.headers.set('x-filename', filename);
    request.headers.set('Content-Type', 'application/octet-stream');
    request.add(bytes);

    final response = await request.close();
    debugPrint('[DEBUG] ShareHandler._uploadFile: response status=${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.statusCode}');
    }
  }
}
