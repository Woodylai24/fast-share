import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a dialog asking the user to copy received clipboard content.
void showClipboardDialog(BuildContext context, String content) {
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
