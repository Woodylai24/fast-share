import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fast_share_mobile/models/message.dart';
import 'package:fast_share_mobile/widgets/summary_bottom_sheet.dart';

/// Shows a bottom sheet with message actions (copy, open, summarize, delete).
void showMessageOptions(
  BuildContext context,
  Message message, {
  required VoidCallback onDelete,
  required Future<void> Function(String url) onOpenUrl,
}) {
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
                onOpenUrl(message.url!);
              },
            ),
            const Divider(height: 1),
          ],
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Summarize'),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => SummaryBottomSheet(message: message),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
    ),
  );
}

/// Shows a confirmation dialog to clear all message history.
void showClearHistoryDialog(BuildContext context, VoidCallback onClear) {
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
            onClear();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text("Clear", style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
