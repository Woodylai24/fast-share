import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fast_share_mobile/models/message.dart';
import 'package:fast_share_mobile/services/chat_notifier.dart';
import 'package:fast_share_mobile/widgets/message_bubble.dart';
import 'package:fast_share_mobile/widgets/chat_app_bar.dart';
import 'package:fast_share_mobile/widgets/message_input.dart';
import 'package:fast_share_mobile/widgets/clipboard_dialog.dart';
import 'package:fast_share_mobile/widgets/file_offer_dialog.dart';
import 'package:fast_share_mobile/widgets/message_actions.dart';
import 'package:fast_share_mobile/widgets/reconnect_banner.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/screens/home_screen.dart';

class ConnectedScreen extends StatefulWidget {
  final String ip;
  final int port;
  final int httpPort;
  final ThemeNotifier themeNotifier;

  const ConnectedScreen({
    super.key,
    required this.ip,
    required this.port,
    required this.httpPort,
    required this.themeNotifier,
  });

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen>
    with WidgetsBindingObserver {
  late final ChatNotifier _notifier;
  final TextEditingController _textController = TextEditingController();

  /// Shows the "Scan QR" action in the initial-connecting banner once the
  /// first connection has been pending for this long without success.
  static const Duration _scanQrActionDelay = Duration(seconds: 10);

  bool _showScanQrAction = false;
  Timer? _scanQrTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notifier = ChatNotifier(
      ip: widget.ip,
      port: widget.port,
      httpPort: widget.httpPort,
    );

    _notifier.init();
    _notifier.setupShareHandler();
    _notifier.addListener(_onNotifierChanged);

    // Arm the Scan-QR fallback for the initial connect. If the first
    // connection succeeds before this fires, the banner disappears and the
    // flag becomes irrelevant.
    _scanQrTimer = Timer(_scanQrActionDelay, () {
      if (mounted && _notifier.isInitialConnecting) {
        setState(() => _showScanQrAction = true);
      }
    });
  }

  /// React to state changes from the notifier that need BuildContext (dialogs, navigation).
  void _onNotifierChanged() {
    if (!mounted) return;

    // Handle pending clipboard dialog
    final clipboard = _notifier.consumePendingClipboard();
    if (clipboard != null) {
      _notifier.setLastReceivedClipboard(clipboard);
      showClipboardDialog(context, clipboard);
    }

    // Handle pending file offer dialog
    final fileOffer = _notifier.consumePendingFileOffer();
    if (fileOffer != null) {
      showFileOfferDialog(context, fileOffer.filename, fileOffer.url);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LIFECYCLE] didChangeAppLifecycleState: $state');
    debugPrint('[LIFECYCLE]   _isDisconnected=${_notifier.isDisconnected}, _isReconnecting=${_notifier.isReconnecting}');
    // Only treat 'resumed' as foreground and 'hidden'/'detached' as background.
    // 'paused' covers quick-settings shade, split-screen, etc. — the app is
    // still partially visible and the OS is unlikely to kill it, so keep the
    // WebSocket alive.
    final isForeground = state == AppLifecycleState.resumed;
    final shouldCloseWs = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    debugPrint('[LIFECYCLE]   isForeground=$isForeground, shouldCloseWs=$shouldCloseWs');
    _notifier.handleAppLifecycleChange(isForeground, shouldCloseWs: shouldCloseWs);
  }

  void _handleUserDisconnect() {
    _notifier.handleUserDisconnect();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(themeNotifier: widget.themeNotifier),
      ),
      (route) => false,
    );
  }

  /// Forget the current pairing and return to the HomeScreen pairing flow.
  /// On the next launch the app opens straight to HomeScreen again until a
  /// new PC is paired.
  Future<void> _handleUnpair() async {
    _notifier.handleUserDisconnect();
    await SettingsService.clearLastConnection();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(themeNotifier: widget.themeNotifier),
      ),
      (route) => false,
    );
  }

  /// Open the pairing flow to re-scan a QR code (e.g. wrong Wi-Fi / PC
  /// offline). Keeps the current pairing until a new one is established.
  void _navigateToHomeForRepair() {
    _notifier.handleUserDisconnect();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(themeNotifier: widget.themeNotifier),
      ),
      (route) => false,
    );
  }

  Future<void> _pickAndSendFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null || _notifier.isDisconnected) return;

    final filePath = result.files.single.path!;
    final filename = result.files.single.name;

    try {
      await _notifier.sendFile(filePath, filename);
    } catch (e) {
      debugPrint('[DEBUG] File send failed: $e');
    }
  }

  @override
  void dispose() {
    _scanQrTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _notifier.removeListener(_onNotifierChanged);
    _notifier.dispose();
    _textController.dispose();
    super.dispose();
  }

  /// Top-of-chat banner. While the very first connection is still pending we
  /// show a "Connecting to PC…" banner (with an optional Scan-QR fallback).
  /// Once the first connection succeeds, later disconnects/reconnects are
  /// handled by the existing ReconnectBanner.
  Widget _buildConnectionBanner() {
    if (_notifier.isInitialConnecting) {
      return _InitialConnectingBanner(
        ip: widget.ip,
        showScanQr: _showScanQrAction,
        onScanQr: _navigateToHomeForRepair,
      );
    }

    return ReconnectBanner(
      isReconnecting: _notifier.showReconnectBanner,
      isDisconnected: _notifier.showReconnectBanner,
      reconnectAttempt: _notifier.reconnectAttempt,
      disconnectReason: _notifier.disconnectReason,
      onConnectPressed: _navigateToHomeForRepair,
      onDisconnectPressed: _handleUserDisconnect,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) {
        return Scaffold(
          appBar: ChatAppBar(
            connectionInfo: widget.ip,
            onDisconnect: _handleUserDisconnect,
            onPickFile: _pickAndSendFile,
            onClearHistory: () => showClearHistoryDialog(
              context,
              _notifier.clearAllMessages,
            ),
            onUnpair: _handleUnpair,
            isDisconnected: _notifier.isDisconnected,
            themeNotifier: widget.themeNotifier,
          ),
          body: Column(
            children: [
              _buildConnectionBanner(),
              Expanded(
                child: ListView.builder(
                  controller: _notifier.scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _notifier.messages.length,
                  itemBuilder: (context, index) {
                    final messages = _notifier.messages;
                    final Message msg = messages[index];
                    final Message? previousMsg =
                        index > 0 ? messages[index - 1] : null;
                    return MessageBubble(
                      message: msg,
                      previousMessage: previousMsg,
                      onTap: () {
                        if (msg.url != null) {
                          openFileUrl(msg.url!);
                        }
                      },
                      onLongPress: () {
                        showMessageOptions(
                          context,
                          msg,
                          onDelete: () => _notifier.deleteMessage(msg),
                          onOpenUrl: openFileUrl,
                        );
                      },
                    );
                  },
                ),
              ),
              MessageInput(
                controller: _textController,
                onSend: () {
                  _notifier.sendText(_textController.text);
                  _textController.clear();
                },
                isDisconnected: _notifier.isDisconnected,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Banner shown while the very first connection attempt is in progress
/// (before the PC has ever responded). Mirrors the look of ReconnectBanner.
class _InitialConnectingBanner extends StatelessWidget {
  final String ip;
  final bool showScanQr;
  final VoidCallback onScanQr;

  const _InitialConnectingBanner({
    required this.ip,
    required this.showScanQr,
    required this.onScanQr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade700,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                showScanQr
                    ? 'Connecting to $ip…'
                    : 'Connecting to PC…',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (showScanQr)
              TextButton(
                onPressed: onScanQr,
                child: const Text(
                  'Scan QR',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
