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
    // Only treat 'resumed' as foreground and 'hidden'/'detached' as background.
    // 'paused' covers quick-settings shade, split-screen, etc. — the app is
    // still partially visible and the OS is unlikely to kill it, so keep the
    // WebSocket alive.
    //
    // Spurious 'resumed' on first background is handled in the notifier via
    // _lastBackgroundAt timestamp guard — resumes within 1s of going to
    // background are ignored.
    if (state == AppLifecycleState.resumed) {
      _notifier.handleAppLifecycleChange(true);
    } else {
      final shouldCloseWs = state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached;
      _notifier.handleAppLifecycleChange(false, shouldCloseWs: shouldCloseWs);
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _notifier.removeListener(_onNotifierChanged);
    _notifier.dispose();
    _textController.dispose();
    super.dispose();
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
            isDisconnected: _notifier.isDisconnected,
            themeNotifier: widget.themeNotifier,
          ),
          body: Column(
            children: [
              ReconnectBanner(
                isReconnecting: _notifier.showReconnectBanner,
                isDisconnected: _notifier.showReconnectBanner,
                reconnectAttempt: _notifier.reconnectAttempt,
                disconnectReason: _notifier.disconnectReason,
                onConnectPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(themeNotifier: widget.themeNotifier),
                    ),
                  );
                },
                onDisconnectPressed: () {
                  _handleUserDisconnect();
                },
              ),
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
