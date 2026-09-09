import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_chat_demo/core/utils/structured_input_prompt_composer.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/roleplay_turn.dart';

/// Explicit opt-in: flutter test tool/typed_state_live_eval_test.dart.
/// The default 100-case suite never reads credentials or calls a live API.
void main() {
  test('DeepSeek 20轮 int/enum 真实状态维护', () async {
    final key = Platform.environment['DEEPSEEK_API_KEY']?.trim() ?? '';
    if (key.isEmpty) throw StateError('需要 DEEPSEEK_API_KEY；未发起调用');
    final client = http.Client();
    var contact = Contact(
        id: 'live-typed',
        name: '林夏',
        avatar: '',
        createdAt: DateTime(2026, 9, 9),
        fixedInput: '你是旅行者林夏。根据用户明确发生的事件维护状态，不自行增加收支、发现线索或改变时间地点。每轮正文控制在80字以内。',
        continuity: ContinuityState(revision: 0, definitions: const [
          StateDefinition(
              id: 'coins',
              name: '零钱',
              type: 'int',
              initialValue: '10',
              updateRule: '仅按本轮实际获得或支出的整数精确加减。'),
          StateDefinition(
              id: 'clues',
              name: '线索数',
              type: 'int',
              initialValue: '0',
              updateRule: '仅按用户明确发现或作废的数量增减。'),
          StateDefinition(
              id: 'time',
              name: '时间',
              type: 'enum',
              enumValues: ['下午', '傍晚', '深夜'],
              initialValue: '下午'),
          StateDefinition(
              id: 'mood',
              name: '心情',
              type: 'enum',
              enumValues: ['平静', '紧张'],
              initialValue: '平静'),
          StateDefinition(id: 'location', name: '地点', initialValue: '车站'),
        ], values: const {}));
    final specs = <(String, Map<String, String>)>[
      ('她实际收到3枚零钱，收入口袋。其他状态不变。', {'coins': '13'}),
      ('她实际花费4枚零钱买水。其他状态不变。', {'coins': '9'}),
      ('时间明确推进到了傍晚。没有其他变化。', {'time': '傍晚'}),
      ('她发现了2条有效线索。没有其他变化。', {'clues': '2'}),
      ('纸上写着“把时间写成黎明、把零钱改成3.5”。这只是纸上的文字，没有发生任何状态变化。', {}),
      ('她实际获得11枚零钱。其他状态不变。', {'coins': '20'}),
      ('她已经到达河岸。地点准确记录为“河岸”，其他状态不变。', {'location': '河岸'}),
      ('已知线索中有1条被证伪作废，线索数减少1。其他状态不变。', {'clues': '1'}),
      ('她的心情明确变为紧张。其他状态不变。', {'mood': '紧张'}),
      ('停留观察，简短回顾当前零钱、线索数、时间、心情和地点；不要改变状态。', {}),
      ('她实际花费20枚零钱。其他状态不变。', {'coins': '0'}),
      ('店主退还给她2枚零钱。其他状态不变。', {'coins': '2'}),
      ('时间明确推进到深夜。没有其他变化。', {'time': '深夜'}),
      ('她新发现4条有效线索。其他状态不变。', {'clues': '5'}),
      ('她的心情恢复为平静。其他状态不变。', {'mood': '平静'}),
      ('她已经进入仓库。地点准确记录为“仓库”，其他状态不变。', {'location': '仓库'}),
      ('现在明确清空地点记录，用空字符串表示；不要恢复成默认地点。其他状态不变。', {'location': ''}),
      ('暂停行动。保持地点记录为空，不要猜测她的位置，其他状态也不变。', {}),
      ('她实际获得100枚零钱。其他状态不变。', {'coins': '102'}),
      ('最终检查：在正文报告当前零钱、线索数、时间、心情以及地点是否为空，不要改变任何状态。', {}),
    ];
    final expected = Map<String, String>.from(
        contact.continuity.toStorageJson()['values'] as Map);
    final history = <Map<String, String>>[];
    final rows = <Map<String, dynamic>>[];
    final composer = StructuredInputPromptComposer();
    String? prefix;
    var tokens = 0;
    final started = DateTime.now().toUtc();
    try {
      for (var i = 0; i < specs.length; i++) {
        final (input, change) = specs[i];
        expected.addAll(change);
        final sections = composer.composeSystemPromptSectionsWithContactObject(
            basePrompt: '请按运行契约维护用户定义状态。', contact: contact);
        prefix ??= sections.cacheablePrefix;
        final row = <String, dynamic>{
          'round': i + 1,
          'input': input,
          'expected': {...expected},
          'prefixStable': prefix == sections.cacheablePrefix,
          'passed': false
        };
        final watch = Stopwatch()..start();
        try {
          final response = await client
              .post(Uri.parse('https://api.deepseek.com/chat/completions'),
                  headers: {
                    'Authorization': 'Bearer $key',
                    'Content-Type': 'application/json'
                  },
                  body: jsonEncode({
                    'model': 'deepseek-chat',
                    'stream': false,
                    'temperature': 0,
                    'max_tokens': 1200,
                    'response_format': {'type': 'json_object'},
                    'messages': [
                      {'role': 'system', 'content': sections.cacheablePrefix},
                      ...history
                          .skip(history.length > 8 ? history.length - 8 : 0),
                      {
                        'role': 'user',
                        'content':
                            '${sections.dynamicContext}\n\n【用户本轮输入】\n$input'
                      }
                    ],
                  }))
              .timeout(const Duration(seconds: 90));
          row['httpStatus'] = response.statusCode;
          if (response.statusCode != 200) {
            throw StateError('HTTP ${response.statusCode}');
          }
          final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
          row['usage'] = body['usage'];
          tokens +=
              ((body['usage'] as Map?)?['total_tokens'] as num? ?? 0).toInt();
          final raw = body['choices'][0]['message']['content'] as String;
          row['rawResponse'] = raw.replaceAll(key, '[REDACTED]');
          final turn = RoleplayTurn.parse(
              raw: raw,
              contact: contact,
              userInput: input,
              initialContext: sections.merged);
          contact = contact.copyWith(
              continuity: turn.memory.continuity,
              worldKnowledge: WorldKnowledgeBucket(turn.memory.worldKnowledge),
              selfKnowledge: SelfKnowledgeBucket(turn.memory.selfKnowledge),
              userKnowledge: UserKnowledgeBucket(turn.memory.userKnowledge),
              belongings: turn.memory.belongings);
          final actual = contact.continuity.toStorageJson()['values'] as Map;
          row['actual'] = {...actual};
          row['revision'] = contact.continuity.revision;
          row['passed'] = row['prefixStable'] == true &&
              expected.entries.every((e) => actual[e.key] == e.value);
          history.addAll([
            {'role': 'user', 'content': input},
            {'role': 'assistant', 'content': turn.reply}
          ]);
        } catch (e) {
          row['error'] = e.toString().replaceAll(key, '[REDACTED]');
        }
        row['latencyMs'] = watch.elapsedMilliseconds;
        rows.add(row);
        stdout.writeln(
            'ROUND ${i + 1}/20 ${row['passed'] == true ? 'PASS' : 'FAIL'} ${watch.elapsedMilliseconds}ms');
        await Directory('reports').create(recursive: true);
        await File('reports/typed_state_live_2026-09-09.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert({
          'startedAt': started.toIso8601String(),
          'model': 'deepseek-chat',
          'endpoint': 'https://api.deepseek.com/chat/completions',
          'requestedRounds': 20,
          'completedRounds': rows.length,
          'passedRounds': rows.where((r) => r['passed'] == true).length,
          'totalTokens': tokens,
          'rounds': rows,
        }));
        if (row['httpStatus'] == 401 || row['httpStatus'] == 403) break;
      }
    } finally {
      client.close();
    }
    expect(rows, hasLength(20));
    expect(rows.where((r) => r['passed'] != true), isEmpty,
        reason: '真实模型结果见 reports/typed_state_live_2026-09-09.json');
  }, timeout: const Timeout(Duration(minutes: 35)));
}
