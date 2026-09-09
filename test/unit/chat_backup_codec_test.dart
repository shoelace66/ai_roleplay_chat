import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/chat_backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = ChatBackupCodec();

  test('备份往返保留消息与事件图，且不包含 API 或设置字段', () {
    final snapshot = ChatSnapshot(
      contacts: <Contact>[
        Contact(
          id: 'role-1',
          name: '林夏',
          avatar: '',
          eventGraph: const EventGraphMemory(turnCount: 7),
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      ],
      messagesByContact: <String, List<Message>>{
        'role-1': <Message>[
          Message(
            id: 'm1',
            role: MessageRole.user,
            content: '你好',
            createdAt: DateTime.fromMillisecondsSinceEpoch(2),
          ),
        ],
      },
    );

    final encoded = codec.encode(
      snapshot,
      exportedAt: DateTime.utc(2026, 7, 27),
    );
    final restored = codec.decode(encoded);

    expect(encoded, contains('"version":3'));
    expect(encoded, isNot(contains('apiKey')));
    expect(encoded, isNot(contains('providerSettings')));
    expect(restored.contacts.single.eventGraph.turnCount, 7);
    expect(restored.messagesByContact['role-1']?.single.content, '你好');
  });

  test('拒绝未知版本和属于不存在联系人的消息', () {
    expect(
      () => codec.decode(
        '{"format":"ai-roleplay-chat-backup","version":3,"contacts":[],"messagesByContact":{}}',
      ),
      throwsFormatException,
    );
    expect(
      () => codec.decode(
        '{"format":"ai-roleplay-chat-backup","version":1,"contacts":[],"messagesByContact":{"missing":[]}}',
      ),
      throwsFormatException,
    );
  });
}
