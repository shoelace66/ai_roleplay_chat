enum MessageRole { user, assistant }

enum MessageStatus {
  sending,
  sent,
  failed,
}

class Message {
  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.sent,
  });

  final String id;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;

  factory Message.fromJson(Map<String, dynamic> json) {
    final roleText = (json['role'] ?? '').toString();
    final statusText = (json['status'] ?? '').toString();
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
      status: MessageStatus.values.firstWhere(
        (e) => e.name == statusText,
        orElse: () => MessageStatus.sent,
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
      'status': status.name,
    };
  }

  Message copyWith({MessageStatus? status}) {
    return Message(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }
}
