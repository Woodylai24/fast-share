import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:fast_share_mobile/models/message.dart';
import 'package:fast_share_mobile/services/message_storage.dart';
import 'package:fast_share_mobile/widgets/message_bubble.dart';
import 'package:fast_share_mobile/widgets/summary_bottom_sheet.dart';
import 'package:fast_share_mobile/screens/home_screen.dart';
import 'package:fast_share_mobile/screens/ai_settings_page.dart';
import 'package:fast_share_mobile/crypto_service.dart';
import 'package:fast_share_mobile/share_handler.dart';
import 'package:fast_share_mobile/services/notifications.dart';

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
        debugPrint(
          '[DEBUG] Received encrypted message before key exchange — dropping',
        );
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
      debugPrint(
        '[DEBUG] Key exchange complete — encrypted channel established',
      );
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
          _showNotification(
            "Clipboard Sync",
            clipboardContent.length > 50
                ? clipboardContent.substring(0, 50) + '...'
                : clipboardContent,
            payload: "COPY:$clipboardContent",
          );
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
    debugPrint(
      '[DEBUG] File transfer starting: ${data['filename']} (${data['fileSize']} bytes)',
    );
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
      debugPrint(
        '[DEBUG] File checksum mismatch: expected ${data['checksum']}, got $checksum',
      );
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
          messages.add(
            Message.image(filename: filename, url: fileUrl, sender: 'PC'),
          );
        } else {
          messages.add(
            Message.file(filename: filename, url: fileUrl, sender: 'PC'),
          );
        }
      });
      _saveMessages();
      _scrollToBottom();

      if (!_isInForeground) {
        _showNotification("File Received", filename, payload: fileUrl);
      }
    }

    debugPrint(
      '[DEBUG] File transfer complete: $filename (${transfer.receivedBytes} bytes)',
    );
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
      channel.sink.add(jsonEncode({'type': 'encrypted', ...encrypted}));
    } catch (e) {
      debugPrint('[DEBUG] Failed to encrypt message, sending plaintext: $e');
      channel.sink.add(jsonEncode(data));
    }
  }

  /// Send a file via encrypted chunked WebSocket transfer.
  Future<void> _sendFileViaWs(String filePath, String filename) async {
    if (!_keyExchangeComplete || !_crypto.isReady) {
      debugPrint(
        '[DEBUG] Key exchange not complete, falling back to HTTP upload',
      );
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
        final end = (offset + chunkSize > fileSize)
            ? fileSize
            : offset + chunkSize;
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

      debugPrint(
        '[DEBUG] File sent via encrypted WS: $filename ($fileSize bytes, $seq chunks)',
      );
    } catch (e) {
      debugPrint(
        '[DEBUG] Failed to send file via WS, falling back to HTTP: $e',
      );
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

  void _setupShareHandler() {
    ShareHandler.setupListener();
    ShareHandler.setContext(context);

    // Register the encrypted send callback
    ShareHandler.registerSendCallback((data) {
      _sendJson(data);
      if (data['type'] == 'text' && data['content'] != null) {
        setState(() {
          messages.add(
            Message.text(content: data['content'] as String, sender: 'Me'),
          );
        });
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
      setState(() {
        if (isImage) {
          messages.add(
            Message.image(filename: filename, url: url, sender: 'Me'),
          );
        } else {
          messages.add(
            Message.file(filename: filename, url: url, sender: 'Me'),
          );
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
        debugPrint(
          '[DEBUG] Saved clipboard state: ${_lastClipboardText?.substring(0, (_lastClipboardText!.length > 30 ? 30 : _lastClipboardText!.length))}...',
        );
      }
    });
  }

  void _checkAndSendClipboard() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text == null) return;
      final currentClipboard = data!.text!;
      if (currentClipboard != _lastClipboardText &&
          currentClipboard != _lastReceivedClipboard) {
        debugPrint(
          '[DEBUG] Clipboard changed while in background, sending to PC',
        );
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
    if (urlString.startsWith('file://')) {
      // Android blocks file:// URIs in Intents — use open_filex instead
      // For now, open in-app or share via system share sheet
      try {
        final filePath = urlString.replaceFirst('file://', '');
        await OpenFilex.open(filePath);
      } catch (e) {
        debugPrint('[DEBUG] Failed to open local file: $e');
      }
      return;
    }
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

      // Use local file path for display (actual transfer is via encrypted WS)
      final fileUrl = 'file://${result.files.single.path}';

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
            icon: const Icon(Icons.settings),
            tooltip: 'AI Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AISettingsPage()),
              );
            },
          ),
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
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Summarize'),
              onTap: () {
                Navigator.pop(context);
                _showSummarizeSheet(message);
              },
            ),
            const Divider(height: 1),
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

  void _showSummarizeSheet(Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SummaryBottomSheet(message: message),
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
