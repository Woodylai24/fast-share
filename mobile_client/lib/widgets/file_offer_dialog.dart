import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';

/// Shows a dialog asking the user to download a received file.
void showFileOfferDialog(BuildContext context, String filename, String url) {
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
            openFileUrl(url);
          },
          child: const Text("Download"),
        ),
      ],
    ),
  );
}

/// Opens a file URL — handles both file:// and http:// URLs.
Future<void> openFileUrl(String urlString) async {
  if (urlString.startsWith('file://')) {
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
