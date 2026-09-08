import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/memory_patch_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reducer = MemoryPatchReducer();

  test('提取正文前本轮事件并保存可回查的原始对话', () {
    final result = reducer.reduce(
      contact: _contact(),
      patch: <String, dynamic>{
        'summary': <String, dynamic>{'description': '此前抵达车站'},
        'eventBrief': <String, dynamic>{
          'description': '林夏把伞递给用户',
          'keywords': <String>['林夏', '伞'],
          'theme': <String>['信任'],
        },
      },
      userInput: '我没有带伞',
      rawAiResponse: '{"memoryPatch":{},"reply":"她把伞柄轻轻递了过来。"}',
    );

    expect(result.summary?.description, '此前抵达车站');
    expect(result.turnEvent?.description, '林夏把伞递给用户');
    expect(result.turnEvent?.sourceDialog, contains('用户：我没有带伞'));
    expect(result.turnEvent?.sourceDialog, contains('AI：她把伞柄轻轻递了过来。'));
  });

  test('状态补丁只能修改用户已经创建的 key', () {
    final result = reducer.reduce(
      contact: _contact(currentStates: const <String, String>{'信任': '低'}),
      patch: <String, dynamic>{
        'currentStates': <String, dynamic>{
          '信任': '中',
          '模型擅自新增': '不允许',
        },
      },
      userInput: '',
      rawAiResponse: '',
    );

    expect(result.currentStates, <String, String>{'信任': '中'});
  });

  test('知识去重且新增和提及物品都会移动到最近位置', () {
    final result = reducer.reduce(
      contact: _contact(
        worldKnowledge: const <String>['旧车站'],
        belongings: const <String>['旧钥匙', '花伞'],
      ),
      patch: <String, dynamic>{
        'worldKnowledge': <String>['旧车站', ' 雨夜 '],
        'belongings': <String>['（提及）花伞', '(新增)车票', '无效格式'],
      },
      userInput: '',
      rawAiResponse: '',
    );

    expect(result.worldKnowledge, <String>['旧车站', '雨夜']);
    expect(result.belongings, <String>['旧钥匙', '花伞', '车票']);
    expect(
      result.belongingChanges.map((change) => change.type),
      <BelongingChangeType>[
        BelongingChangeType.mentioned,
        BelongingChangeType.added,
      ],
    );
  });

  test('结构化记忆操作可以替换删除旧知识并移除物品', () {
    final result = reducer.reduce(
      contact: _contact(
        worldKnowledge: const <String>['林夏住在北京', '雨城常年多雨'],
        selfKnowledge: const <String>['我不会游泳'],
        userKnowledge: const <String>['用户讨厌咖啡'],
        belongings: const <String>['旧钥匙', '车票'],
      ),
      patch: <String, dynamic>{
        'knowledgeChanges': <Map<String, String>>[
          {
            'scope': 'world',
            'operation': 'replace',
            'from': '林夏住在北京',
            'to': '林夏已经搬到上海',
          },
          {
            'scope': 'self',
            'operation': 'remove',
            'from': '我不会游泳',
          },
          {
            'scope': 'user',
            'operation': 'add',
            'to': '用户喜欢红茶',
          },
        ],
        'belongingChanges': <Map<String, String>>[
          {'operation': 'remove', 'item': '车票'},
          {'operation': 'add', 'item': '雨伞'},
        ],
      },
      userInput: '',
      rawAiResponse: '',
    );

    expect(result.worldKnowledge, ['林夏已经搬到上海', '雨城常年多雨']);
    expect(result.selfKnowledge, isEmpty);
    expect(result.userKnowledge, ['用户讨厌咖啡', '用户喜欢红茶']);
    expect(result.belongings, ['旧钥匙', '雨伞']);
    expect(result.belongingChanges.first.type, BelongingChangeType.removed);
  });
}

Contact _contact({
  Map<String, String> currentStates = const <String, String>{},
  List<String> worldKnowledge = const <String>[],
  List<String> selfKnowledge = const <String>[],
  List<String> userKnowledge = const <String>[],
  List<String> belongings = const <String>[],
}) {
  return Contact(
    id: 'contact-1',
    name: '林夏',
    avatar: '',
    currentStates: currentStates,
    worldKnowledge: WorldKnowledgeBucket(worldKnowledge),
    selfKnowledge: SelfKnowledgeBucket(selfKnowledge),
    userKnowledge: UserKnowledgeBucket(userKnowledge),
    belongings: belongings,
    createdAt: DateTime(2026),
  );
}
