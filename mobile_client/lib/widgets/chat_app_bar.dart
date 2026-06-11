import 'package:flutter/material.dart';
import 'package:fast_share_mobile/screens/settings_screen.dart';
import 'package:fast_share_mobile/screens/file_browser_screen.dart';
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
      title: Text('Fast Share'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onDisconnect,
      ),
      actions: [
        // Folder icon — navigate to file browser
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: 'Files',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FileBrowserScreen(),
              ),
            );
          },
        ),
        // Settings
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
        // File upload
        IconButton(
          icon: const Icon(Icons.file_upload),
          onPressed: isDisconnected ? null : onPickFile,
        ),
        // Clear history
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: 'Clear History',
          onPressed: onClearHistory,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
