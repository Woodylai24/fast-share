import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'package:cryptography/cryptography.dart';

/// Manages WebSocket connection, E2EE, messages, file transfer, and clipboard sync.
/// Used by ConnectedScreen via ListenableBuilder.

// ─── Isolate functions for background crypto (prevents UI freeze) ─────

/// Decrypt a file in a background isolate using a one-time AES-256-GCM key.
/// Must be top-level for compute() to access it.
Future<Uint8List> _decryptFileInIsolate(Map<String, List<int>> args) async {
  final aesGcm = AesGcm.with256bits();
  final secretBox = SecretBox(
    args['encrypted']!,
    nonce: args['nonce']!,
    mac: Mac(args['mac']!),
  );
  final decrypted = await aesGcm.decrypt(
    secretBox,
    secretKey: SecretKey(args['key']!),
  );
  return Uint8List.fromList(decrypted);
}

/// Encrypt a file in a background isolate using a one-time AES-256-GCM key.
/// Key and nonce are generated in the caller and passed in so they can be
/// reused for the WS metadata message. Returns encrypted bytes + GCM mac.
Future<Map<String, Uint8List>> _encryptFileInIsolate(Map<String, List<int>> args) async {
  final aesGcm = AesGcm.with256bits();
  final secretBox = await aesGcm.encrypt(
    args['data']!,
    secretKey: SecretKey(args['key']!),
    nonce: args['nonce']!,
  );
  return {
    'encrypted': Uint8List.fromList(secretBox.cipherText),
    'mac': Uint8List.fromList(secretBox.mac.bytes),
  };
}

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

  /// True once the first connection has been fully established (key exchange
  /// complete). Used to distinguish the very first connect attempt from later
  /// reconnects so the UI can show a distinct "Connecting to PC…" state.
  bool _everConnected = false;

  /// True while the first connection attempt is in progress (before the first
  /// successful connection). Drives the WhatsApp-like "Connecting to PC…"
  /// banner shown on launch.
  bool get isInitialConnecting => !_everConnected && !_intentionalDisconnect;

  /// Whether the reconnect/disconnect banner should be visible.
  /// Suppresses both banners on the first reconnect attempt (e.g. returning
  /// from background) so the user doesn't see a flash before the connection
  /// is quickly restored. Shows on subsequent failures.
  bool get showReconnectBanner {
    if (!_isDisconnected && !_isReconnecting) return false;
    // Hide during first reconnect attempt
    if (_isReconnecting && _reconnectAttempt <= 1) return false;
    return true;
  }

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

  // Progress throttle — last notified progress percentage (0-100)
  int _lastNotifiedProgress = -1;

  // Reconnect with backoff
  static const int _initialReconnectDelay = 1; // seconds
  static const int _maxReconnectDelay = 30;    // seconds
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  // Connection watchdog: detects silent disconnect (e.g. WiFi disabled).
  // Server sends pings every 30s. If we don't receive ANY message for 45s,
  // the connection is dead.
  DateTime? _lastServerMessageAt;
  Timer? _watchdogTimer;
  static const Duration _watchdogInterval = Duration(seconds: 10);
  static const Duration _watchdogTimeout = Duration(seconds: 45);

  // Pending message queue (Phase 3)
  final List<Message> _pendingMessages = [];

  // Message ACK tracking (two-way delivery confirmation)
  // Maps messageId → timer. When the timer fires, the message was not
  // acknowledged → connection is dead → move to pending queue.
  final Map<String, Timer> _pendingAcks = {};
  static const Duration _ackTimeout = Duration(seconds: 15);
  // Dedup: tracks recently seen incoming messageIds
  final Set<String> _recentMessageIds = {};
  static const int _maxRecentIds = 200;

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
    debugPrint('[LIFECYCLE] _connect() called — creating WebSocket to $wsUrl');

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
      // Must NOT be reconnecting and key exchange must be complete.
      // Without _keyExchangeComplete, _sendJson falls back to plaintext,
      // which means messages sent during reconnect are unencrypted.
      // Without !_isReconnecting, messages are sent over a half-open
      // channel that hasn't completed the handshake yet.
      return !_isDisconnected &&
          !_isReconnecting &&
          _keyExchangeComplete &&
          channel.closeCode == null;
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
    debugPrint('[LIFECYCLE] _performReconnectAttempt #$_reconnectAttempt — _isDisconnected=$_isDisconnected, _isReconnecting=$_isReconnecting');
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
            if (!_isDisconnected && !_intentionalDisconnect) {
              _tryReconnect(); // Retry
            }
          },
          onDone: () {
            debugPrint('[DEBUG] Reconnect attempt $_reconnectAttempt failed (done)');
            if (!_isDisconnected && !_intentionalDisconnect) {
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

  // ─── Connection watchdog ────────────────────────────────────────────

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _lastServerMessageAt = DateTime.now();
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      if (_isDisconnected || _intentionalDisconnect) {
        _watchdogTimer?.cancel();
        return;
      }
      if (_lastServerMessageAt == null) return;
      final elapsed = DateTime.now().difference(_lastServerMessageAt!);
      if (elapsed > _watchdogTimeout) {
        debugPrint('[WATCHDOG] No server message for ${elapsed.inSeconds}s — treating as disconnected');
        _watchdogTimer?.cancel();
        handleDisconnect('Connection timed out');
      }
    });
    debugPrint('[WATCHDOG] Started — timeout: ${_watchdogTimeout.inSeconds}s');
  }

  int get reconnectAttempt => _reconnectAttempt;

  // ─── Message ACK helpers ────────────────────────────────────────────

  String _generateMessageId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
  }

  /// Track an outgoing message. If no ACK arrives within 15s, the
  /// connection is dead — move the message to the pending queue and
  /// trigger disconnect.
  void _trackPendingAck(String messageId) {
    _pendingAcks.remove(messageId)?.cancel();
    _pendingAcks[messageId] = Timer(_ackTimeout, () {
      _handleAckTimeout(messageId);
    });
  }

  /// Called when the PC acknowledges receipt of our message.
  void _handleAckReceived(String messageId) {
    _pendingAcks.remove(messageId)?.cancel();
    debugPrint('[DEBUG] ACK received for message: $messageId');
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(deliveryStatus: 'delivered');
      notifyListeners();
      _saveMessages();
    }
  }

  /// Called when the ACK timer fires — message was not acknowledged.
  /// The connection is likely dead.
  void _handleAckTimeout(String messageId) {
    _pendingAcks.remove(messageId);
    debugPrint('[DEBUG] ACK timeout for message: $messageId');

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final msg = _messages[idx];
      if (msg.deliveryStatus == 'sent') {
        _messages[idx] = msg.copyWith(deliveryStatus: 'pending');
        _pendingMessages.add(msg.copyWith(deliveryStatus: 'pending'));
      }
    }
    notifyListeners();

    // Connection is dead — trigger disconnect + reconnect
    if (!_isDisconnected) {
      handleDisconnect('Connection lost (message not acknowledged)');
    }
  }

  /// Cancel all pending ACK timers and move unacked 'sent' messages to the
  /// pending queue for retransmission. Called on disconnect, background, and dispose.
  void _cancelAllPendingAcks() {
    for (final messageId in _pendingAcks.keys.toList()) {
      _pendingAcks[messageId]?.cancel();
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx >= 0 && _messages[idx].deliveryStatus == 'sent') {
        _messages[idx] = _messages[idx].copyWith(deliveryStatus: 'pending');
        _pendingMessages.add(_messages[idx]);
      }
    }
    _pendingAcks.clear();
  }

  /// Add a messageId to the dedup set, capping the set size.
  void _addRecentMessageId(String messageId) {
    if (_recentMessageIds.length >= _maxRecentIds) {
      _recentMessageIds.remove(_recentMessageIds.first);
    }
    _recentMessageIds.add(messageId);
  }

  // ─── Pending message flush (Phase 3) ─────────────────────────────────

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    debugPrint('[DEBUG] Flushing ${_pendingMessages.length} pending messages');
    for (final msg in _pendingMessages) {
      _sendJson({'type': 'text', 'content': msg.content, 'messageId': msg.id});
      // Update status to 'sent' and track ACK
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) {
        _messages[idx] = msg.copyWith(deliveryStatus: 'sent');
      }
      _trackPendingAck(msg.id);
    }
    _pendingMessages.clear();
    notifyListeners();
    _saveMessages();
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────

  void handleAppLifecycleChange(bool isInForeground, {bool shouldCloseWs = true}) {
    debugPrint('[LIFECYCLE] handleAppLifecycleChange: isInForeground=$isInForeground, shouldCloseWs=$shouldCloseWs');
    debugPrint('[LIFECYCLE]   state: _isDisconnected=$_isDisconnected, _isReconnecting=$_isReconnecting, _intentionalDisconnect=$_intentionalDisconnect, _isConnected=${_isConnected()}');
    _isInForeground = isInForeground;
    notifyListeners();

    if (isInForeground) {
      if (!_intentionalDisconnect && !_isConnected()) {
        debugPrint('[LIFECYCLE]   → calling _attemptReconnectIfEnabled');
        _attemptReconnectIfEnabled();
      } else {
        debugPrint('[LIFECYCLE]   → skipping reconnect (intentionalDisconnect=$_intentionalDisconnect, isConnected=${_isConnected()})');
      }
      checkAndSendClipboard();
    } else if (shouldCloseWs) {
      saveCurrentClipboard();
      // Close WebSocket cleanly when truly backgrounded (hidden/detached).
      // Skipped for 'paused' state (quick-settings shade, split-screen, etc.)
      if (_isConnected() && !_intentionalDisconnect) {
        debugPrint('[LIFECYCLE]   → closing WS with code 4000');
        // Set _isDisconnected BEFORE closing the socket. On the first
        // (local, fresh) connection, channel.sink.close() can complete
        // almost instantly, firing the onDone callback as a microtask
        // before we reach the _isDisconnected = true line below. The
        // onDone handler checks !_isDisconnected and would call
        // handleDisconnect → _attemptReconnectIfEnabled, creating the
        // phantom reconnect.
        _isDisconnected = true;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _isReconnecting = false;
        _watchdogTimer?.cancel();
        // Cancel pending ACKs and move unacked messages to pending queue.
        // They'll be re-sent when the app returns to foreground.
        _cancelAllPendingAcks();
        channel.sink.close(4000, 'app_backgrounded');
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
    _lastServerMessageAt = DateTime.now();

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
      _handleKeyExchange(data['publicKey'] as String);
      // _flushPendingMessages is called from _handleKeyExchange after
      // key exchange completes, so messages are sent encrypted.
      return;
    }

    if (msgType == 'handshake') {
      debugPrint('[DEBUG] Received handshake from server');
      if (_isReconnecting) {
        _cancelReconnect();
      }
      _isDisconnected = false;
      _reconnectAttempt = 0;
      return;
    }

    // --- ACK from PC (delivery confirmation for messages we sent) ---
    if (msgType == 'message-ack') {
      final messageId = data['messageId'] as String?;
      if (messageId != null) {
        _handleAckReceived(messageId);
      }
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
      _everConnected = true;
      _keyExchangeTimeout?.cancel();

      final ourPublicKey = await _crypto.getPublicKeyBase64();
      _sendJson({'type': 'key-exchange', 'publicKey': ourPublicKey});
      debugPrint(
        '[DEBUG] Key exchange complete — encrypted channel established',
      );

      // Flush pending messages now that encryption is established.
      // Previously this was called before _handleKeyExchange, which sent
      // messages as plaintext (keyExchangeComplete was still false).
      _flushPendingMessages();

      // Flush pending files (queued because file picker/share closed the WS).
      // Send sequentially — PC receiver only tracks one incoming file at a time.
      if (_pendingFiles.isNotEmpty) {
        final files = List<({String path, String name})>.from(_pendingFiles);
        _pendingFiles.clear();
        for (final f in files) {
          debugPrint('[DEBUG] Sending pending file after reconnect: ${f.name}');
          // Remove the placeholder we added in sendFile — sendFile will
          // create a proper one with transfer tracking
          _messages.removeWhere((m) =>
              m.filename == f.name && m.sender == 'Me' &&
              m.transferState == TransferState.pending);
          await sendFile(f.path, f.name);
        }
      }

      _startWatchdog();
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

    // --- Send ACK back to PC for delivery confirmation ---
    final messageId = data['messageId'] as String?;
    if (messageId != null) {
      // Dedup: skip if already processed (original arrived but ACK was lost)
      if (_recentMessageIds.contains(messageId)) {
        debugPrint('[DEBUG] Duplicate message, re-ACKing without processing: $messageId');
        _sendJson({'type': 'message-ack', 'messageId': messageId});
        return;
      }
      _addRecentMessageId(messageId);
      _sendJson({'type': 'message-ack', 'messageId': messageId});
      debugPrint('[DEBUG] Sent ACK for message: $messageId');
    }

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

      case 'file-upload-ready':
        final requestId = data['requestId'] as String;
        final uploadToken = data['uploadToken'] as String;
        // Construct URL from the IP we're connected to — the PC's getLocalIp()
        // may return a wrong virtual adapter (e.g., WSL2, VPN) that's unreachable.
        final uploadUrl = 'http://$ip:${data['httpPort'] ?? httpPort}/encrypted-upload/$uploadToken';
        final completer = _pendingUploads.remove(requestId);
        completer?.complete(uploadUrl);
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

  Future<void> _handleFileStart(Map<String, dynamic> data) async {
    final filename = data['filename'] as String;
    final fileSize = data['fileSize'] as int;
    final downloadUrl = data['downloadUrl'] as String;
    final keyBase64 = data['key'] as String;
    final nonceBase64 = data['nonce'] as String;
    final tagBase64 = data['tag'] as String;

    debugPrint('[DEBUG] File transfer starting: $filename ($fileSize bytes)');

    final isImage = RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(filename);
    final placeholder = Message.transferPlaceholder(
      filename: filename,
      sender: 'PC',
      type: isImage ? MessageType.image : MessageType.file,
      transferState: TransferState.pending,
      transferProgress: 0.0,
    );
    _messages.add(placeholder);
    _lastNotifiedProgress = 0;
    notifyListeners();
    _scrollToBottom();

    try {
      // Update to transferring state
      _updateMessageById(placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.transferring,
          transferProgress: 0.0,
        ));
      notifyListeners();

      // Download encrypted blob with progress tracking
      final response = await http.Client().send(http.Request('GET', Uri.parse(downloadUrl)));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final encryptedBytes = <int>[];
      await for (final chunk in response.stream) {
        encryptedBytes.addAll(chunk);
        final progress = fileSize > 0 ? encryptedBytes.length / fileSize : 0.0;
        final currentPct = (progress * 100).toInt();
        if (currentPct - _lastNotifiedProgress >= 5 || progress >= 1.0) {
          _lastNotifiedProgress = currentPct;
          _updateMessageById(placeholder.id,
            _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
              transferProgress: progress,
            ));
          notifyListeners();
        }
      }

      // Decrypt in background isolate (prevents UI freeze on large files)
      final decrypted = await compute(_decryptFileInIsolate, {
        'encrypted': encryptedBytes,
        'key': base64Decode(keyBase64),
        'nonce': base64Decode(nonceBase64),
        'mac': base64Decode(tagBase64),
      });

      // Save to FastShare dir
      final fastShareDir = await FileStorage.getFastShareDir();
      final localFile = File('${fastShareDir.path}/$filename');
      await localFile.writeAsBytes(decrypted);
      if (isImage) {
        await FileStorage.scanFile(localFile.path);
      }

      // Update placeholder to complete
      _updateMessageById(placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.complete,
          transferProgress: 1.0,
          url: 'file://${localFile.path}',
        ));
      notifyListeners();
      _saveMessages();
      _scrollToBottom();
      debugPrint('[DEBUG] File received and decrypted: $filename');
    } catch (e) {
      debugPrint('[DEBUG] File download/decrypt failed: $e');
      _updateMessageById(placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.failed,
        ));
      notifyListeners();
    }
  }

  // ─── Sending ─────────────────────────────────────────────────────────

  void sendText(String text) {
    if (text.isEmpty) return;
    final messageId = _generateMessageId();

    if (_isConnected()) {
      _sendJson({'type': 'text', 'content': text, 'messageId': messageId});
      final msg = Message.text(content: text, sender: 'Me')
          .copyWith(id: messageId, deliveryStatus: 'sent');
      _messages.add(msg);
      _trackPendingAck(messageId);
    } else {
      // Queue locally with pending status
      final msg = Message.text(content: text, sender: 'Me')
          .copyWith(id: messageId, deliveryStatus: 'pending');
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

  // Pending files — saved when file picker/share closes the WS mid-send.
  // Each entry stores the path + filename to flush after reconnect.
  final List<({String path, String name})> _pendingFiles = [];

  // Pending file uploads — maps messageId → Completer for upload URL
  final Map<String, Completer<String>> _pendingUploads = {};

  Future<void> sendFile(String filePath, String filename) async {
    if (_isDisconnected || !_keyExchangeComplete || !_crypto.isReady) {
      debugPrint('[DEBUG] sendFile: not connected, queuing file for after reconnect');
      _pendingFiles.add((path: filePath, name: filename));

      final isImage = RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(filename);
      final placeholder = Message.transferPlaceholder(
        filename: filename,
        sender: 'Me',
        type: isImage ? MessageType.image : MessageType.file,
        transferState: TransferState.pending,
        transferProgress: 0.0,
      );
      _messages.add(placeholder);
      _scrollToBottom();
      notifyListeners();
      return;
    }

    final isImage = RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(filename);
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

      _updateMessageById(placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.transferring,
          transferProgress: 0.0,
        ));
      notifyListeners();

      // Encrypt file with one-time key in background isolate
      final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
      final encResult = await compute(_encryptFileInIsolate, {
        'data': fileBytes,
        'key': key,
        'nonce': nonce,
      });
      final messageId = placeholder.id;
      final mimeType = _getMimeType(filename);

      // Send metadata via E2EE WS — PC responds with upload URL
      _sendEncrypted({
        'type': 'file-upload-request',
        'filename': filename,
        'fileSize': fileBytes.length,
        'mimeType': mimeType,
        'key': base64Encode(key),
        'nonce': base64Encode(nonce),
        'tag': base64Encode(encResult['mac']!),
        'messageId': messageId,
      });

      // Wait for PC to respond with upload URL
      final uploadUrlCompleter = Completer<String>();
      _pendingUploads[messageId] = uploadUrlCompleter;

      // Track ACK BEFORE upload — PC sends ACK immediately after decryption,
      // which can arrive while the upload is still in progress. If we track
      // after the upload, the ACK is already missed and the 15s timer fires.
      _trackPendingAck(messageId);

      final uploadUrl = await uploadUrlCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('PC did not respond to upload request'),
      );

      // Upload encrypted blob via HTTP
      final uploadRequest = http.StreamedRequest('POST', Uri.parse(uploadUrl));
      uploadRequest.contentLength = encResult['encrypted']!.length;
      uploadRequest.sink.add(encResult['encrypted']!);
      uploadRequest.sink.close();

      final uploadResponse = await uploadRequest.send();
      if (uploadResponse.statusCode != 200) {
        throw Exception('Upload failed: HTTP ${uploadResponse.statusCode}');
      }

      // Mark as complete
      _updateMessageById(placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.complete,
          transferProgress: 1.0,
          url: 'file://$filePath',
          deliveryStatus: 'sent',
        ));
      _lastNotifiedProgress = -1;
      notifyListeners();
      _saveMessages();
      _scrollToBottom();
      debugPrint('[DEBUG] File uploaded: $filename (${fileBytes.length} bytes)');
    } catch (e) {
      debugPrint('[DEBUG] Failed to send file: $e');
      _updateMessageById(placeholder.id,
        _messages.firstWhere((m) => m.id == placeholder.id).copyWith(
          transferState: TransferState.failed,
        ));
      notifyListeners();
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
    _watchdogTimer?.cancel();
    _keyExchangeTimeout?.cancel();

    // Cancel pending ACK timers and move unacked messages to pending queue.
    // These messages were sent but never confirmed — the connection is dead,
    // so they'll be re-sent on reconnect. Dedup on the PC side prevents
    // duplicates if the original message actually arrived.
    _cancelAllPendingAcks();

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

    _cancelAllPendingAcks();
    _keyExchangeTimeout?.cancel();

    _sendJson({'type': 'disconnect', 'reason': 'user_initiated'});
    debugPrint('[DEBUG] Sent disconnect message to PC');

    channel.sink.close();
    notifyListeners();
  }

  /// Unpair from the PC — sends an unpair message so the PC removes this
  /// device from its pairedDevices store, then disconnects.
  void handleUnpair() {
    if (!_isDisconnected) {
      _sendJson({'type': 'unpair', 'deviceId': _deviceId});
      debugPrint('[DEBUG] Sent unpair message to PC');
    }
    handleUserDisconnect();
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

    // Route shared text through sendText() — handles connection check,
    // queueing, ACK tracking, and delivery status.
    ShareHandler.registerTextCallback((text) {
      sendText(text);
    });

    // Route shared files through sendFile() — handles connection check,
    // queueing, messageId in file-end, ACK tracking, placeholder messages.
    // Must be async so multiple shared files send sequentially (PC receiver
    // only tracks one incoming file at a time).
    ShareHandler.registerFileCallback((filePath, filename) {
      return sendFile(filePath, filename);
    });
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cancelAllPendingAcks();
    _clipboardPollTimer?.cancel();
    _reconnectTimer?.cancel();
    _keyExchangeTimeout?.cancel();
    _watchdogTimer?.cancel();
    ShareHandler.unregisterCallbacks();
    _subscription?.cancel();
    channel.sink.close();
    scrollController.dispose();
    super.dispose();
  }
}
