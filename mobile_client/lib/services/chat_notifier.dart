import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fast_share_mobile/services/file_storage.dart';
import 'package:fast_share_mobile/models/message.dart';
import 'package:fast_share_mobile/services/message_storage.dart';
import 'package:fast_share_mobile/services/notifications.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/crypto_service.dart';
import 'package:fast_share_mobile/share_handler.dart';

/// Incoming file transfer state for reassembly
class _IncomingFileTransfer {
  final String filename;
  final int fileSize;
  final String mimeType;
  final List<Uint8List> chunks = [];
  int receivedBytes = 0;
  Timer? _timer;
  String? messageId; // ID of the placeholder Message in the message list

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

/// Manages WebSocket connection, E2EE, messages, file transfer, and clipboard sync.
/// Used by ConnectedScreen via ListenableBuilder.
class ChatNotifier extends ChangeNotifier {
  final String ip;
  final int port;
  final int httpPort;

  // WebSocket
  late WebSocketChannel channel;
  StreamSubscription? _subscription;

  // Messages
  final List<Message> _messages = [];
  List<Message> get messages => List.unmodifiable(_messages);

  // Connection state
  bool _isDisconnected = false;
  bool get isDisconnected => _isDisconnected;

  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  /// Whether the reconnect banner should be visible.
  /// Suppresses the banner on the first reconnect attempt (e.g. returning
  /// from background) so the user doesn't see a flash of "Reconnecting..."
  /// before the connection is quickly restored.
  bool get showReconnectBanner => _isReconnecting && _reconnectAttempt > 1;

  bool _isInForeground = true;
  bool get isInForeground => _isInForeground;

  // Clipboard
  String? _lastClipboardText;
  String? _lastReceivedClipboard;
  Timer? _clipboardPollTimer;

  // Device ID
  static String? _deviceId;

  // Intentional disconnect flag
  bool _intentionalDisconnect = false;

  // E2EE
  final CryptoService _crypto = CryptoService();
  bool _keyExchangeComplete = false;
  bool get keyExchangeComplete => _keyExchangeComplete;
  Timer? _keyExchangeTimeout;

  // File transfer
  _IncomingFileTransfer? _incomingFile;

  // Progress throttle — last notified progress percentage (0-100)
  int _lastNotifiedProgress = -1;

  // Reconnect with backoff
  static const int _initialReconnectDelay = 1; // seconds
  static const int _maxReconnectDelay = 30;    // seconds
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  // Pending message queue (Phase 3)
  final List<Message> _pendingMessages = [];

  // Scroll control (exposed for the widget to use)
  final ScrollController scrollController = ScrollController();

  ChatNotifier({
    required this.ip,
    required this.port,
    required this.httpPort,
  });

  /// Initialize everything — call from initState.
  void init() {
    _initDeviceId();
    _loadSavedMessages();
    _connect();
    _startClipboardPolling();
  }

  // ─── Device ID ───────────────────────────────────────────────────────

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
    }
    debugPrint('[DEBUG] Device ID: $_deviceId');
  }

  // ─── Message persistence ─────────────────────────────────────────────

  Future<void> _loadSavedMessages() async {
    final savedMessages = await MessageStorageService.loadMessages();
    if (savedMessages.isNotEmpty) {
      _messages.addAll(savedMessages);
      notifyListeners();
      _scrollToBottom();
    }
  }

  Future<void> _saveMessages() async {
    await MessageStorageService.saveMessages(_messages);
  }

  void _scrollToBottom() {
    if (scrollController.hasClients) {
      // Use jumpTo with a very large offset — Flutter clamps it to
      // maxScrollExtent automatically. This avoids the stale-extent bug
      // where animateTo(maxScrollExtent) targets a value that's one item
      // behind because layout hasn't caught up yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  // ─── Connection ──────────────────────────────────────────────────────

  Future<void> _connect() async {
    final wsUrl = Uri.parse('ws://$ip:$port');
    debugPrint('[DEBUG] ChatNotifier: Connecting to $wsUrl');

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
          if (!_isDisconnected) {
            _messages.add(
              Message.text(content: message.toString(), sender: 'PC'),
            );
            notifyListeners();
            _saveMessages();
            _scrollToBottom();
          }
        }
      },
      onError: (error) {
        debugPrint('[DEBUG] WebSocket ERROR: $error');
        if (!_isDisconnected && !_intentionalDisconnect) {
          handleDisconnect('Connection error');
        }
      },
      onDone: () {
        debugPrint('[DEBUG] WebSocket connection CLOSED');
        if (!_isDisconnected && !_intentionalDisconnect) {
          handleDisconnect('Connection lost');
        }
      },
    );

    // Send handshake with device ID and FCM token
    final prefs = await SharedPreferences.getInstance();
    final fcmToken = prefs.getString('fcm_token');
    _sendJson({
      'type': 'handshake',
      'device': 'Mobile',
      'deviceId': _deviceId,
      'fcmToken': fcmToken,
    });
    debugPrint(
      '[DEBUG] ChatNotifier: Handshake sent with deviceId: $_deviceId, fcmToken: $fcmToken',
    );
  }

  bool _isConnected() {
    try {
      return !_isDisconnected && channel.closeCode == null;
    } catch (e) {
      return false;
    }
  }

  Future<void> attemptReconnect() async {
    if (_isReconnecting || _intentionalDisconnect) return;

    _isReconnecting = true;
    _reconnectAttempt = 0;
    notifyListeners();
    debugPrint('[DEBUG] Starting reconnect with exponential backoff...');
    _tryReconnect();
  }

  void _tryReconnect() {
    if (_intentionalDisconnect) {
      _cancelReconnect();
      return;
    }

    // Calculate delay with exponential backoff
    final delaySeconds = (_initialReconnectDelay * (1 << _reconnectAttempt)).clamp(1, _maxReconnectDelay);
    _reconnectAttempt++;
    debugPrint('[DEBUG] Reconnect attempt $_reconnectAttempt, waiting ${delaySeconds}s...');
    notifyListeners();

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _performReconnectAttempt();
    });
  }

  void _performReconnectAttempt() {
    try {
      _subscription?.cancel();
      _crypto.init().then((_) {
        _keyExchangeComplete = false;

        final wsUrl = Uri.parse('ws://$ip:$port');
        channel = WebSocketChannel.connect(wsUrl);

        _subscription = channel.stream.listen(
          (message) {
            debugPrint('[DEBUG] Received message on reconnect: $message');
            try {
              final data = jsonDecode(message);
              _handleRawMessage(data);
            } catch (e) {
              debugPrint('[DEBUG] Failed to parse message: $e');
            }
          },
          onError: (error) {
            debugPrint('[DEBUG] Reconnect attempt $_reconnectAttempt failed (error): $error');
            _tryReconnect(); // Retry
          },
          onDone: () {
            debugPrint('[DEBUG] Reconnect attempt $_reconnectAttempt failed (done)');
            if (!_intentionalDisconnect) {
              _tryReconnect(); // Retry
            }
          },
        );

        // Reset disconnected flag — we have a fresh WebSocket now.
        // The old flag was set for the previous dead connection.
        // Without this, _sendJson's guard at the top silently drops the
        // reconnect message, the server never receives it, and the 5s
        // key-exchange timer fires → connection closed.
        _isDisconnected = false;

        _sendJson({'type': 'reconnect', 'deviceId': _deviceId});
        debugPrint('[DEBUG] Reconnect message sent for attempt $_reconnectAttempt');
      });
    } catch (e) {
      debugPrint('[DEBUG] Reconnect attempt $_reconnectAttempt exception: $e');
      _tryReconnect(); // Retry
    }
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempt = 0;
    notifyListeners();
  }

  int get reconnectAttempt => _reconnectAttempt;

  // ─── Pending message flush (Phase 3) ─────────────────────────────────

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    debugPrint('[DEBUG] Flushing ${_pendingMessages.length} pending messages');
    for (final msg in _pendingMessages) {
      _sendJson({'type': 'text', 'content': msg.content});
      // Update status to 'sent'
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) {
        _messages[idx] = msg.copyWith(deliveryStatus: 'sent');
      }
    }
    _pendingMessages.clear();
    notifyListeners();
    _saveMessages();
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────

  void handleAppLifecycleChange(bool isInForeground, {bool shouldCloseWs = true}) {
    _isInForeground = isInForeground;
    notifyListeners();

    if (isInForeground) {
      if (!_intentionalDisconnect && !_isConnected()) {
        _attemptReconnectIfEnabled();
      }
      checkAndSendClipboard();
    } else if (shouldCloseWs) {
      saveCurrentClipboard();
      // Close WebSocket cleanly when truly backgrounded (hidden/detached).
      // Skipped for 'paused' state (quick-settings shade, split-screen, etc.)
      if (_isConnected() && !_intentionalDisconnect) {
        debugPrint('[DEBUG] App backgrounded — closing WebSocket with code 4000');
        channel.sink.close(4000, 'app_backgrounded');
        _isDisconnected = true;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _isReconnecting = false;
      }
    }
  }

  /// Checks the autoReconnect setting before attempting reconnect.
  Future<void> _attemptReconnectIfEnabled() async {
    final autoReconnect = await SettingsService.getAutoReconnect();
    if (!autoReconnect) {
      debugPrint(
        '[DEBUG] Auto-reconnect is disabled, showing disconnected state',
      );
      return;
    }
    debugPrint('[DEBUG] App resumed, attempting reconnect...');
    attemptReconnect();
  }

  // ─── Message handling (raw) ──────────────────────────────────────────

  void _handleRawMessage(Map<String, dynamic> data) {
    final String msgType = data['type'] ?? '';

    // Handle ping — respond with pong (plaintext, before encrypted check)
    if (msgType == 'ping') {
      channel.sink.add(jsonEncode({'type': 'pong'}));
      debugPrint('[DEBUG] Received ping, sent pong');
      return;
    }

    if (msgType == 'key-exchange') {
      debugPrint('[DEBUG] Received key-exchange from server');
      if (_isReconnecting) {
        _cancelReconnect();
      }
      _isDisconnected = false;
      _flushPendingMessages();
      _handleKeyExchange(data['publicKey'] as String);
      return;
    }

    if (msgType == 'handshake') {
      debugPrint('[DEBUG] Received handshake from server');
      if (_isReconnecting) {
        _cancelReconnect();
      }
      _isDisconnected = false;
      return;
    }

    if (msgType == 'encrypted') {
      if (!_keyExchangeComplete) {
        debugPrint(
          '[DEBUG] Received encrypted message before key exchange — dropping',
        );
        return;
      }
      _handleEncryptedMessage(data);
      return;
    }

    if (msgType == 'disconnect') {
      final reason = data['reason'] ?? 'PC disconnected';
      debugPrint('[DEBUG] Received disconnect message: $reason');
      _intentionalDisconnect = true;
      if (!_isDisconnected) {
        handleDisconnect(reason);
      }
      return;
    }

    _handleIncomingMessage(data);
  }

  // ─── E2EE ────────────────────────────────────────────────────────────

  Future<void> _handleKeyExchange(String serverPublicKey) async {
    try {
      await _crypto.computeSharedSecret(serverPublicKey);
      _keyExchangeComplete = true;
      _keyExchangeTimeout?.cancel();

      final ourPublicKey = await _crypto.getPublicKeyBase64();
      _sendJson({'type': 'key-exchange', 'publicKey': ourPublicKey});
      debugPrint(
        '[DEBUG] Key exchange complete — encrypted channel established',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[DEBUG] Key exchange failed: $e');
    }
  }

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

  // ─── Incoming message dispatch ───────────────────────────────────────

  Future<void> _handleIncomingMessage(Map<String, dynamic> data) async {
    final String msgType = data['type'] ?? 'text';

    if (_isDisconnected) return;

    switch (msgType) {
      case 'text':
        final content = data['content'] ?? '';
        _messages.add(Message.text(content: content, sender: 'PC'));
        notifyListeners();
        _scrollToBottom();
        _saveMessages();
        if (!_isInForeground) {
          showLocalNotification("New Message", content, payload: "COPY:$content");
        }
        break;

      case 'handshake':
        break;

      case 'file':
        final filename = data['filename'] ?? 'Unknown file';
        final url = data['url'] ?? '';
        _messages.add(Message.file(filename: filename, url: url, sender: 'PC'));
        notifyListeners();
        _scrollToBottom();
        _saveMessages();
        if (!_isInForeground) {
          showLocalNotification("File Received", filename, payload: url);
        }
        break;

      case 'image':
        final filename = data['filename'] ?? 'Unknown image';
        final url = data['url'] ?? '';
        _messages.add(Message.image(filename: filename, url: url, sender: 'PC'));
        notifyListeners();
        _saveMessages();
        if (!_isInForeground) {
          showLocalNotification("Image Received", filename, payload: url);
        }
        break;

      case 'clipboard':
        final clipboardContent = data['content'] ?? '';
        // Incoming clipboard is ALWAYS auto-copied regardless of local setting
        // The clipboard sync setting only controls OUTGOING behavior
        _lastReceivedClipboard = clipboardContent;
        _lastClipboardText = clipboardContent;
        await Clipboard.setData(ClipboardData(text: clipboardContent));
        showLocalNotification(
          "Clipboard Synced",
          clipboardContent.length > 50
              ? clipboardContent.substring(0, 50) + '...'
              : clipboardContent,
        );
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
        _messages.add(Message.file(filename: filename, url: url, sender: 'PC'));
        notifyListeners();
        _saveMessages();
        if (!_isInForeground) {
          showLocalNotification("File Received", filename, payload: url);
        }
        _pendingFileOffer = (filename: filename, url: url);
        notifyListeners();
        break;
    }

    _scrollToBottom();
  }

  // ─── Pending UI actions (consumed by the widget) ────────────────────

  String? _pendingClipboard;
  String? consumePendingClipboard() {
    final val = _pendingClipboard;
    _pendingClipboard = null;
    return val;
  }

  ({String filename, String url})? _pendingFileOffer;
  ({String filename, String url})? consumePendingFileOffer() {
    final val = _pendingFileOffer;
    _pendingFileOffer = null;
    return val;
  }

  // ─── Helper: update a message in-place by ID ────────────────────────

  /// Find a message by ID in _messages and replace it with [updated].
  /// Returns true if found.
  bool _updateMessageById(String id, Message updated) {
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].id == id) {
        _messages[i] = updated;
        return true;
      }
    }
    return false;
  }

  // ─── File transfer ──────────────────────────────────────────────────

  void _handleFileStart(Map<String, dynamic> data) {
    debugPrint(
      '[DEBUG] File transfer starting: ${data['filename']} (${data['fileSize']} bytes)',
    );
    _incomingFile?._cleanup();
    _incomingFile = _IncomingFileTransfer(
      filename: data['filename'] as String,
      fileSize: data['fileSize'] as int,
      mimeType: data['mimeType'] as String? ?? 'application/octet-stream',
    );

    // Create a placeholder message immediately for progress UI
    final filename = _incomingFile!.filename;
    final isImage = RegExp(
      r'\.(jpg|jpeg|png|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(filename);

    final placeholder = Message.transferPlaceholder(
      filename: filename,
      sender: 'PC',
      type: isImage ? MessageType.image : MessageType.file,
      transferState: TransferState.pending,
      transferProgress: 0.0,
    );
    _incomingFile!.messageId = placeholder.id;
    _messages.add(placeholder);
    _lastNotifiedProgress = 0;
    notifyListeners();
    _scrollToBottom();
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

    // Throttled progress update: notify only every 5% change
    final progress = _incomingFile!.fileSize > 0
        ? _incomingFile!.receivedBytes / _incomingFile!.fileSize
        : 0.0;
    final currentPct = (progress * 100).toInt();
    if (currentPct - _lastNotifiedProgress >= 5) {
      _lastNotifiedProgress = currentPct;
      final msgId = _incomingFile!.messageId;
      if (msgId != null) {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            transferState: TransferState.transferring,
            transferProgress: progress,
          );
          notifyListeners();
        }
      }
    }
  }

  Future<void> _handleFileEnd(Map<String, dynamic> data) async {
    if (_incomingFile == null) {
      debugPrint('[DEBUG] Received file-end without file-start — ignoring');
      return;
    }

    final transfer = _incomingFile!;
    _incomingFile = null;
    transfer._cancelTimer();

    final assembled = <int>[];
    for (final chunk in transfer.chunks) {
      assembled.addAll(chunk);
    }

    final checksum = await CryptoService.sha256(assembled);
    if (checksum != data['checksum']) {
      debugPrint(
        '[DEBUG] File checksum mismatch: expected ${data['checksum']}, got $checksum',
      );
      // Mark the placeholder as failed
      final msgId = transfer.messageId;
      if (msgId != null) {
        _updateMessageById(
          msgId,
          _messages.firstWhere((m) => m.id == msgId).copyWith(
            transferState: TransferState.failed,
          ),
        );
        notifyListeners();
      }
      return;
    }

    final filename = transfer.filename;
    final isImage = RegExp(
      r'\.(jpg|jpeg|png|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(filename);

    String fileUrl;
    try {
      final fastShareDir = await FileStorage.getFastShareDir();
      final localFile = File('${fastShareDir.path}/$filename');
      await localFile.writeAsBytes(assembled);
      fileUrl = 'file://${localFile.path}';
      debugPrint('[DEBUG] File saved locally: ${localFile.path}');
      // Scan image files so they appear in Gallery
      if (isImage) {
        await FileStorage.scanFile(localFile.path);
      }
    } catch (e) {
      debugPrint('[DEBUG] Failed to save file locally: $e');
      fileUrl = 'http://$ip:$httpPort/files/${Uri.encodeComponent(filename)}';
    }

    if (!_isDisconnected) {
      // Update the placeholder message to complete with the actual URL
      final msgId = transfer.messageId;
      if (msgId != null) {
        final updated = _updateMessageById(
          msgId,
          _messages.firstWhere((m) => m.id == msgId).copyWith(
            transferState: TransferState.complete,
            transferProgress: 1.0,
            url: fileUrl,
          ),
        );
        if (!updated) {
          // Fallback: add a new message if placeholder was removed
          if (isImage) {
            _messages.add(Message.image(filename: filename, url: fileUrl, sender: 'PC'));
          } else {
            _messages.add(Message.file(filename: filename, url: fileUrl, sender: 'PC'));
          }
        }
      } else {
        // No placeholder — add a new message (legacy path)
        if (isImage) {
          _messages.add(Message.image(filename: filename, url: fileUrl, sender: 'PC'));
        } else {
          _messages.add(Message.file(filename: filename, url: fileUrl, sender: 'PC'));
        }
      }
      notifyListeners();
      _saveMessages();
      _scrollToBottom();

      if (!_isInForeground) {
        showLocalNotification("File Received", filename, payload: fileUrl);
      }
    }

    debugPrint(
      '[DEBUG] File transfer complete: $filename (${transfer.receivedBytes} bytes)',
    );
  }

  // ─── Sending ─────────────────────────────────────────────────────────

  void sendText(String text) {
    if (text.isEmpty) return;

    if (_isConnected()) {
      _sendJson({'type': 'text', 'content': text});
      _messages.add(Message.text(content: text, sender: 'Me'));
    } else {
      // Queue locally with pending status
      final msg = Message.text(content: text, sender: 'Me')
          .copyWith(deliveryStatus: 'pending');
      _pendingMessages.add(msg);
      _messages.add(msg);
      debugPrint('[DEBUG] Queued pending message (${_pendingMessages.length} pending)');
    }
    notifyListeners();
    _saveMessages();
    _scrollToBottom();
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_isDisconnected) return;

    final type = data['type'] as String?;

    if (type != null && isUnencryptedType(type)) {
      channel.sink.add(jsonEncode(data));
      return;
    }

    if (_keyExchangeComplete && _crypto.isReady) {
      _sendEncrypted(data);
    } else {
      channel.sink.add(jsonEncode(data));
    }
  }

  void _sendEncrypted(Map<String, dynamic> data) async {
    try {
      final encrypted = await _crypto.encrypt(data);
      channel.sink.add(jsonEncode({'type': 'encrypted', ...encrypted}));
    } catch (e) {
      debugPrint('[DEBUG] Failed to encrypt message, sending plaintext: $e');
      channel.sink.add(jsonEncode(data));
    }
  }

  Future<void> sendFile(String filePath, String filename) async {
    if (_isDisconnected) return;

    if (!_keyExchangeComplete || !_crypto.isReady) {
      debugPrint(
        '[DEBUG] Key exchange not complete, falling back to HTTP upload',
      );
      await _uploadFileViaHttp(filePath, filename);
      return;
    }

    // Determine message type (image vs file)
    final isImage = RegExp(
      r'\.(jpg|jpeg|png|gif|webp|bmp)$',
      caseSensitive: false,
    ).hasMatch(filename);

    // Create a placeholder message for the outgoing transfer
    final placeholder = Message.transferPlaceholder(
      filename: filename,
      sender: 'Me',
      type: isImage ? MessageType.image : MessageType.file,
      transferState: TransferState.pending,
      transferProgress: 0.0,
    );
    _messages.add(placeholder);
    _lastNotifiedProgress = 0;
    notifyListeners();
    _scrollToBottom();

    try {
      final file = File(filePath);
      final fileBytes = await file.readAsBytes();
      final fileSize = fileBytes.length;
      final mimeType = _getMimeType(filename);
      final checksum = await CryptoService.sha256(fileBytes);

      // Update to transferring state
      _updateMessageById(
        placeholder.id,
        placeholder.copyWith(
          transferState: TransferState.transferring,
          transferProgress: 0.0,
        ),
      );
      notifyListeners();

      _sendEncrypted({
        'type': 'file-start',
        'filename': filename,
        'fileSize': fileSize,
        'mimeType': mimeType,
      });

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

        // Throttled progress update every ~5% or every 10 chunks
        if (fileSize > 0 && (seq % 10 == 0 || offset >= fileSize)) {
          final progress = offset / fileSize;
          final currentPct = (progress * 100).toInt();
          if (currentPct - _lastNotifiedProgress >= 5 || offset >= fileSize) {
            _lastNotifiedProgress = currentPct;
            _updateMessageById(
              placeholder.id,
              _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
                transferProgress: progress,
              ),
            );
            notifyListeners();
          }
        }
      }

      _sendEncrypted({
        'type': 'file-end',
        'filename': filename,
        'checksum': checksum,
      });

      // Mark as complete — set url to local file path so it can be opened
      _updateMessageById(
        placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.complete,
          transferProgress: 1.0,
          url: 'file://$filePath',
        ),
      );
      _lastNotifiedProgress = -1;
      notifyListeners();
      _saveMessages();
      _scrollToBottom();

      debugPrint(
        '[DEBUG] File sent via encrypted WS: $filename ($fileSize bytes, $seq chunks)',
      );
    } catch (e) {
      debugPrint(
        '[DEBUG] Failed to send file via WS, falling back to HTTP: $e',
      );
      // Mark the placeholder as failed, then fall back to HTTP
      _updateMessageById(
        placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.failed,
        ),
      );
      notifyListeners();
      await _uploadFileViaHttp(filePath, filename);
    }
  }

  Future<void> _uploadFileViaHttp(String filePath, String filename) async {
    try {
      var request = http.StreamedRequest(
        'POST',
        Uri.parse('http://$ip:$httpPort/upload'),
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
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'txt': 'text/plain',
      'json': 'application/json',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  // ─── Clipboard ───────────────────────────────────────────────────────

  void _startClipboardPolling() {
    _clipboardPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isInForeground && !_isDisconnected) {
        checkAndSendClipboard();
      }
    });
  }

  void saveCurrentClipboard() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text != null) {
        _lastClipboardText = data!.text;
        debugPrint(
          '[DEBUG] Saved clipboard state: ${_lastClipboardText?.substring(0, (_lastClipboardText!.length > 30 ? 30 : _lastClipboardText!.length))}...',
        );
      }
    });
  }

  void checkAndSendClipboard() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text == null) return;
      final currentClipboard = data!.text!;
      if (currentClipboard != _lastClipboardText &&
          currentClipboard != _lastReceivedClipboard) {
        // Check outgoing clipboard setting — only send if not 'none'
        SettingsService.getClipboardSync().then((clipboardSync) {
          if (clipboardSync == 'none') return;
          debugPrint(
            '[DEBUG] Clipboard changed while in background, sending to PC',
          );
          if (clipboardSync == 'auto-message') {
            // 'auto-message' — send as regular text message
            _sendJson({'type': 'text', 'content': currentClipboard});
          } else {
            // 'auto-sync' — send as clipboard sync
            _sendJson({'type': 'clipboard', 'content': currentClipboard});
          }
          _lastClipboardText = currentClipboard;
        });
      }
    });
  }

  void setLastReceivedClipboard(String? text) {
    _lastReceivedClipboard = text;
  }

  String? get lastReceivedClipboard => _lastReceivedClipboard;

  // ─── Disconnect ──────────────────────────────────────────────────────

  /// Maps raw disconnect reasons / close codes to user-friendly messages.
  String _friendlyDisconnectReason(String? rawReason, [int? closeCode]) {
    if (rawReason != null && rawReason.isNotEmpty) {
      if (rawReason.contains('Connection timed out')) {
        return 'Connection timed out — PC may be offline';
      }
      if (rawReason.contains('Connection error')) {
        return 'Could not reach PC — are you on the same WiFi?';
      }
      if (rawReason.contains('Connection lost')) {
        return 'Connection lost — your WiFi may have dropped';
      }
      return rawReason;
    }

    switch (closeCode) {
      case 1006:
        return 'Connection lost — your WiFi may have dropped';
      case 4001:
        return 'Connection timed out — PC may be offline';
      case 1000:
        return 'PC disconnected';
      case 1001:
        return 'PC is shutting down';
      default:
        return 'Connection lost';
    }
  }

  void handleDisconnect(String reason) {
    if (_isDisconnected) return;
    _isDisconnected = true;

    _reconnectTimer?.cancel(); // Cancel any in-progress reconnect
    _incomingFile?._cleanup();
    _incomingFile = null;
    _keyExchangeTimeout?.cancel();

    channel.sink.close();
    _disconnectReason = _friendlyDisconnectReason(reason);
    notifyListeners();

    // Auto-reconnect unless intentional
    if (!_intentionalDisconnect) {
      _attemptReconnectIfEnabled();
    }
  }

  void handleUserDisconnect() {
    if (_isDisconnected) return;
    _isDisconnected = true;
    _intentionalDisconnect = true;

    _incomingFile?._cleanup();
    _incomingFile = null;
    _keyExchangeTimeout?.cancel();

    _sendJson({'type': 'disconnect', 'reason': 'user_initiated'});
    debugPrint('[DEBUG] Sent disconnect message to PC');

    channel.sink.close();
    notifyListeners();
  }

  String? _disconnectReason;
  String? get disconnectReason => _disconnectReason;

  // ─── Message management ──────────────────────────────────────────────

  void deleteMessage(Message message) {
    _messages.removeWhere((m) => m.id == message.id);
    notifyListeners();
    _saveMessages();
  }

  void clearAllMessages() {
    _messages.clear();
    notifyListeners();
    MessageStorageService.clearMessages();
  }

  // ─── Share handler ───────────────────────────────────────────────────

  void setupShareHandler() {
    ShareHandler.setupListener();

    ShareHandler.registerSendCallback((data) {
      _sendJson(data);
      if (data['type'] == 'text' && data['content'] != null) {
        _messages.add(
          Message.text(content: data['content'] as String, sender: 'Me'),
        );
        notifyListeners();
        _saveMessages();
        _scrollToBottom();
      }
    });

    ShareHandler.registerLocalMessageCallback((fileInfo) {
      final filename = fileInfo['filename'] ?? 'Unknown';
      final url = fileInfo['url'] ?? '';
      final isImage =
          filename.toLowerCase().endsWith('.jpg') ||
          filename.toLowerCase().endsWith('.jpeg') ||
          filename.toLowerCase().endsWith('.png') ||
          filename.toLowerCase().endsWith('.gif') ||
          filename.toLowerCase().endsWith('.webp') ||
          filename.toLowerCase().endsWith('.bmp');
      if (isImage) {
        _messages.add(Message.image(filename: filename, url: url, sender: 'Me'));
      } else {
        _messages.add(Message.file(filename: filename, url: url, sender: 'Me'));
      }
      notifyListeners();
      _saveMessages();
      _scrollToBottom();
    });
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _clipboardPollTimer?.cancel();
    _reconnectTimer?.cancel();
    _keyExchangeTimeout?.cancel();
    _incomingFile?._cleanup();
    ShareHandler.unregisterSendCallback();
    _subscription?.cancel();
    channel.sink.close();
    scrollController.dispose();
    super.dispose();
  }
}
