enum MessageRole { user, assistant }

class Message {
  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  factory Message.fromJson(Map<String, dynamic> json) {
    final roleText = (json['role'] ?? '').toString();
    return Message(
      id: (json['id'] ?? '').toString(),
      role: roleText == MessageRole.assistant.name
          ? MessageRole.assistant
          : MessageRole.user,
      content: (json['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(
            (json['createdAtMs'] is num)
                ? (json['createdAtMs'] as num).toInt()
                : 0,
          ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'role': role.name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'createdAtMs': createdAt.millisecondsSinceEpoch,
    };
  }
}
