import 'package:flutter/material.dart';
import 'package:fast_share_mobile/screens/settings_screen.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String connectionInfo;
  final VoidCallback onDisconnect;
  final VoidCallback onPickFile;
  final VoidCallback onClearHistory;
  final bool isDisconnected;
  final ThemeNotifier themeNotifier;

  const ChatAppBar({
    super.key,
    required this.connectionInfo,
    required this.onDisconnect,
    required this.onPickFile,
    required this.onClearHistory,
    this.isDisconnected = false,
    required this.themeNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text('Connected to $connectionInfo'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onDisconnect,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsScreen(themeNotifier: themeNotifier),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.file_upload),
          onPressed: isDisconnected ? null : onPickFile,
        ),
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Clear History',
          onPressed: onClearHistory,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Disconnect',
          onPressed: onDisconnect,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
