/// Message types enum
enum MessageType { text, file, image }

/// Transfer state for file/image messages
enum TransferState { pending, transferring, complete, failed }

/// Message model class
class Message {
  final String id;
  final MessageType type;
  final String content;
  final String? url;
  final String sender; // 'PC' or 'Me' or 'System'
  final String? filename;
  final DateTime timestamp;

  // Transfer progress fields
  final TransferState? transferState;
  final double transferProgress; // 0.0 to 1.0

  // Delivery status for local message queue
  final String deliveryStatus; // 'pending' | 'sent' | 'delivered'

  Message({
    String? id,
    required this.type,
    required this.content,
    this.url,
    required this.sender,
    this.filename,
    DateTime? timestamp,
    this.transferState,
    this.transferProgress = 0.0,
    this.deliveryStatus = 'sent',
  }) : id =
           id ??
           '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}',
       timestamp = timestamp ?? DateTime.now();

  /// Create a text message
  factory Message.text({required String content, required String sender}) {
    return Message(type: MessageType.text, content: content, sender: sender);
  }

  /// Create a file message
  factory Message.file({
    required String filename,
    required String url,
    required String sender,
  }) {
    return Message(
      type: MessageType.file,
      content: filename,
      filename: filename,
      url: url,
      sender: sender,
    );
  }

  /// Create an image message
  factory Message.image({
    required String filename,
    required String url,
    required String sender,
  }) {
    return Message(
      type: MessageType.image,
      content: filename,
      filename: filename,
      url: url,
      sender: sender,
    );
  }

  /// Create a system message
  factory Message.system({required String content}) {
    return Message(type: MessageType.text, content: content, sender: 'System');
  }

  /// Create a placeholder message for an in-progress file transfer
  factory Message.transferPlaceholder({
    required String filename,
    required String sender,
    required MessageType type,
    TransferState transferState = TransferState.pending,
    double transferProgress = 0.0,
  }) {
    return Message(
      type: type,
      content: filename,
      filename: filename,
      sender: sender,
      transferState: transferState,
      transferProgress: transferProgress,
    );
  }

  /// Create a copy with updated fields (used for progress updates)
  Message copyWith({
    String? id,
    MessageType? type,
    String? content,
    String? url,
    String? sender,
    String? filename,
    DateTime? timestamp,
    TransferState? transferState,
    double? transferProgress,
    String? deliveryStatus,
  }) {
    return Message(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      url: url ?? this.url,
      sender: sender ?? this.sender,
      filename: filename ?? this.filename,
      timestamp: timestamp ?? this.timestamp,
      transferState: transferState ?? this.transferState,
      transferProgress: transferProgress ?? this.transferProgress,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'url': url,
    'sender': sender,
    'filename': filename,
    'timestamp': timestamp.toIso8601String(),
    'deliveryStatus': deliveryStatus,
    // Don't persist transfer state — completed transfers have null state
    // and in-progress transfers shouldn't be persisted mid-way
  };

  /// Create from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String?,
      type: MessageType.values.firstWhere((e) => e.name == json['type']),
      content: json['content'] as String,
      url: json['url'] as String?,
      sender: json['sender'] as String,
      filename: json['filename'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      deliveryStatus: (json['deliveryStatus'] as String?) ?? 'sent',
    );
  }

  bool get isMe => sender == 'Me';
  bool get isPC => sender == 'PC';
  bool get isSystem => sender == 'System';

  /// Whether this message is currently being transferred
  bool get isTransferring =>
      transferState == TransferState.transferring ||
      transferState == TransferState.pending;

  /// Whether this message had a failed transfer
  bool get isTransferFailed => transferState == TransferState.failed;
}
