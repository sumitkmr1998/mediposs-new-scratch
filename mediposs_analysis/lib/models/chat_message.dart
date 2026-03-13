class ChatMessage {
  final String id;
  final String threadId;
  final String role; // 'user' or 'ai'
  String content; // Changed from final to support streaming updates
  final String? imagePath; // Path or base64 if needed, keeping it simple
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.content,
    this.imagePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'threadId': threadId,
      'role': role,
      'content': content,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      threadId: map['threadId'],
      role: map['role'],
      content: map['content'],
      imagePath: map['imagePath'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
