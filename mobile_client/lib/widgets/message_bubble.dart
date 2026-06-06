import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fast_share_mobile/models/message.dart';

/// Format time for message timestamp
String formatMessageTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Format date for day separator
String formatDaySeparator(DateTime date) {
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);

  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'Today';
  } else if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Yesterday';
  } else {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Extension for DateTime to compare dates
extension DateTimeExtension on DateTime {
  String toDateString() {
    return '$year-$month-$day';
  }
}

/// Message bubble widget that displays different UI based on message type
class MessageBubble extends StatelessWidget {
  final Message message;
  final Message? previousMessage;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    this.previousMessage,
    this.onTap,
    this.onLongPress,
  });

  bool get _showDaySeparator {
    if (previousMessage == null) return true;
    return message.timestamp.toDateString() !=
        previousMessage!.timestamp.toDateString();
  }

  bool get _showTimestamp {
    return true;
  }

  /// Whether this message bubble should show a progress indicator
  bool get _isTransferring {
    final state = message.transferState;
    return state == TransferState.pending ||
        state == TransferState.transferring;
  }

  /// Whether this transfer failed
  bool get _isTransferFailed => message.transferState == TransferState.failed;

  @override
  Widget build(BuildContext context) {
    // System messages are centered
    if (message.isSystem) {
      return Column(
        children: [
          if (_showDaySeparator) _buildDaySeparator(message.timestamp),
          _buildSystemBubble(),
        ],
      );
    }

    // Align based on sender
    final isMe = message.isMe;
    return Column(
      children: [
        if (_showDaySeparator) _buildDaySeparator(message.timestamp),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.sender,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                _buildMessageContent(context, isMe),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaySeparator(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              formatDaySeparator(date),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildSystemBubble() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, bool isMe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        InkWell(
          onLongPress: onLongPress,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: _buildBubbleContent(context, isMe),
        ),
        if (_showTimestamp)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Text(
              formatMessageTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.blue[200] : Colors.grey[500],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBubbleContent(BuildContext context, bool isMe) {
    switch (message.type) {
      case MessageType.text:
        return _buildTextBubble(context, isMe);
      case MessageType.file:
        return _buildFileBubble(context, isMe);
      case MessageType.image:
        return _buildImageBubble(context, isMe);
    }
  }

  Widget _buildTextBubble(BuildContext context, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[400] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Linkify(
        text: message.content,
        style: TextStyle(
          fontSize: 16,
          color: isMe ? Colors.white : Colors.black87,
        ),
        linkStyle: TextStyle(
          fontSize: 16,
          color: isMe ? Colors.white : Colors.blue,
          decoration: TextDecoration.underline,
        ),
        onOpen: (link) async {
          final Uri url = Uri.parse(link.url);
          if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
            // URL launch failed
          }
        },
      ),
    );
  }

  /// Build a progress overlay widget for file/image transfers
  Widget _buildProgressOverlay(bool isMe) {
    if (!_isTransferring && !_isTransferFailed) return const SizedBox.shrink();

    final progress = message.transferProgress;
    final percent = (progress * 100).toInt();
    final state = message.transferState;

    // Failed state
    if (_isTransferFailed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 16),
            const SizedBox(width: 6),
            Text(
              'Transfer failed',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[400],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Pending / transferring state
    final isSending = message.isMe;
    final label = state == TransferState.pending
        ? (isSending ? 'Preparing...' : 'Waiting...')
        : (isSending ? 'Sending... $percent%' : 'Receiving... $percent%');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == TransferState.pending)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isMe ? Colors.blue[300] : Colors.grey[500],
                ),
              )
            else
              Icon(
                isSending ? Icons.upload : Icons.download,
                size: 14,
                color: isMe ? Colors.blue[300] : Colors.grey[500],
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.blue[300] : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: state == TransferState.pending ? null : progress,
            minHeight: 4,
            backgroundColor: isMe ? Colors.blue[100] : Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              isMe ? Colors.blue[400]! : Colors.grey[600]!,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileBubble(BuildContext context, bool isMe) {
    final iconData = _getFileIcon(message.filename ?? '');
    final iconColor = _getFileIconColor(message.filename ?? '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? Colors.blue[200]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconData, color: iconColor, size: 32),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.filename ?? 'Unknown file',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isTransferring || _isTransferFailed
                          ? ''
                          : 'Tap to download',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Progress indicator for file transfers
          if (_isTransferring || _isTransferFailed) ...[
            const SizedBox(height: 8),
            _buildProgressOverlay(isMe),
          ],
        ],
      ),
    );
  }

  Widget _buildImageBubble(BuildContext context, bool isMe) {
    // If still transferring, show a placeholder with progress
    if (_isTransferring || _isTransferFailed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe ? Colors.blue[200]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, color: Colors.grey, size: 32),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.filename ?? 'Image',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildProgressOverlay(isMe),
          ],
        ),
      );
    }

    final String? url = message.url;

    // Handle local file:// URLs vs remote http:// URLs
    final bool isLocalFile = url != null && url.startsWith('file://');

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
        child: url != null
            ? isLocalFile
                  ? Image.file(
                      File(url.replaceFirst('file://', '')),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 40,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Failed to load',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[200],
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 40,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Failed to load',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
            : Container(
                color: Colors.grey[200],
                child: const Icon(Icons.image, size: 40, color: Colors.grey),
              ),
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Icons.video_file;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.orange;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}
