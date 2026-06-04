/// Message types enum
enum MessageType { text, file, image }

/// Message model class
class Message {
  final String id;
  final MessageType type;
  final String content;
  final String? url;
  final String sender; // 'PC' or 'Me' or 'System'
  final String? filename;
  final DateTime timestamp;

  Message({
    String? id,
    required this.type,
    required this.content,
    this.url,
    required this.sender,
    this.filename,
    DateTime? timestamp,
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

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'content': content,
    'url': url,
    'sender': sender,
    'filename': filename,
    'timestamp': timestamp.toIso8601String(),
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
    );
  }

  bool get isMe => sender == 'Me';
  bool get isPC => sender == 'PC';
  bool get isSystem => sender == 'System';
}
