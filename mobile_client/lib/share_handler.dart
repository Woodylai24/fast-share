import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Utility to handle incoming shares from Android OS (PROCESS_TEXT, SEND, SEND_MULTIPLE).
/// Routes shared content through ChatNotifier's sendText/sendFile methods,
/// which handle connection checks, ACK tracking, and offline queueing.
class ShareHandler {
  static const MethodChannel _channel = MethodChannel('fast_share/share_receiver');

  static void Function(Map<String, dynamic>)? _textSendCallback;
  static Future<void> Function(String, String)? _fileSendCallback;
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

  /// Register callback for shared text. Receives the raw text string.
  static void registerTextCallback(void Function(String text) callback) {
    _textSendCallback = (data) {
      callback(data['content'] as String);
    };
  }

  /// Register callback for shared files. Receives (filePath, filename) pairs.
  /// Must be async — files are sent sequentially, each must complete before
  /// the next starts (PC receiver only tracks one incoming file at a time).
  static void registerFileCallback(Future<void> Function(String filePath, String filename) callback) {
    _fileSendCallback = callback;
  }

  static void unregisterCallbacks() {
    _textSendCallback = null;
    _fileSendCallback = null;
  }

  static Future<void> _processPendingShare() async {
    if (_pendingShare == null) return;
    final share = _pendingShare!;
    _pendingShare = null;

    debugPrint('[DEBUG] ShareHandler: processing share type=${share['type']}');

    try {
      final type = share['type']!;
      final data = share['data']!;

      if (type == 'text') {
        if (_textSendCallback != null) {
          _textSendCallback!({'type': 'text', 'content': data});
        } else {
          debugPrint('[DEBUG] ShareHandler: no text callback registered');
        }
      } else if (type == 'file' || type == 'files') {
        if (_fileSendCallback == null) {
          debugPrint('[DEBUG] ShareHandler: no file callback registered');
          return;
        }

        final uris = type == 'files' ? data.split(',') : [data];

        for (final uriString in uris) {
          try {
            debugPrint('[DEBUG] ShareHandler: resolving URI $uriString');
            final filePath = await _resolveContentUri(uriString);
            debugPrint('[DEBUG] ShareHandler: resolved to $filePath');
            if (filePath != null) {
              final filename = filePath.split('/').last;
                await _fileSendCallback!(filePath, filename);
            }
          } catch (e) {
            debugPrint('[DEBUG] ShareHandler file error: $e');
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
}
