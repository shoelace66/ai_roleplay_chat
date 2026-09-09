import 'dart:async';
import 'dart:convert';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/event_recall_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventRecallCoordinator', () {
    test('明确结构化词项在 L0 完成且不调用模型', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('key', 10, keywords: const <String>['银钥匙']),
          ],
        ),
        currentInput: '她把银钥匙交给了我',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          requestBudget.tryConsumePost();
          return '{}';
        },
      );

      expect(calls, 0);
      expect(result.phase, RecallPhase.local);
      expect(result.postCount, 0);
      expect(result.nodes.map((node) => node.id), <String>['key']);
      expect(result.activeTerms, <String>['银钥匙']);
    });

    test('近期结构化锚点触发 PLAN，并在候选明确时只调用一次', () async {
      var calls = 0;
      LlmProfile? seenProfile;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: <EventNode>[
            _node('linxia', 10, keywords: const <String>['林夏']),
          ],
        ),
        currentInput: '她后来怎么样了？',
        recentMessages: const <RecallDialogueMessage>[
          RecallDialogueMessage(role: 'assistant', content: '林夏转身离开了车站。'),
        ],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: _profile('cheap'),
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          seenProfile = profile;
          expect(requestBudget.tryConsumePost(), isTrue);
          final alias = _catalogAlias(prompt, 'k', '林夏');
          return jsonEncode(<String, dynamic>{
            'v': 1,
            'action': 'search',
            'k': <String>[alias],
            't': <String>[],
            'r': <String>[],
            'recency': 'any',
            'confidence': 'high',
          });
        },
      );

      expect(calls, 1);
      expect(result.postCount, 1);
      expect(result.phase, RecallPhase.plan);
      expect(result.nodes.single.id, 'linxia');
      expect(seenProfile?.model, 'cheap');
      expect(seenProfile?.parameters.temperature, 0);
      expect(seenProfile?.parameters.maxTokens, 128);
      expect(seenProfile?.parameters.timeoutSeconds, 12);
      expect(seenProfile?.parameters.stream, isFalse);
    });

    test('候选边界模糊时 PLAN 后进入 JUDGE，总共两次调用', () async {
      var calls = 0;
      final graph = EventGraphMemory(
        longTermQueue: List<EventNode>.generate(
          6,
          (index) => _node(
            'event-$index',
            index,
            keywords: const <String>['钥匙'],
          ),
        ),
      );
      final result = await EventRecallCoordinator().recall(
        graph: graph,
        currentInput: '钥匙的事情',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          expect(requestBudget.tryConsumePost(), isTrue);
          if (prompt.startsWith('event-recall-plan-v1')) {
            final alias = _catalogAlias(prompt, 'k', '钥匙');
            return jsonEncode(<String, dynamic>{
              'v': 1,
              'action': 'search',
              'k': <String>[alias],
              't': <String>[],
              'r': <String>[],
              'recency': 'any',
              'confidence': 'medium',
            });
          }
          expect(prompt.startsWith('event-recall-judge-v1'), isTrue);
          expect(profile.parameters.maxTokens, 96);
          expect(prompt.runes.length, lessThanOrEqualTo(4800));
          final payload =
              jsonDecode(prompt.substring(prompt.indexOf('DATA=') + 5))
                  as Map<String, dynamic>;
          final cards = (payload['candidates'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(cards, hasLength(6));
          expect(
            cards.first.keys.toSet(),
            <String>{
              'id',
              'description',
              'keywords',
              'themes',
              'relations',
              'tier',
              'writeOrder',
              'status',
              'graphDistance',
            },
          );
          return '{"v":1,"selected":["E1"],"confidence":"high"}';
        },
      );

      expect(calls, 2);
      expect(result.postCount, 2);
      expect(result.phase, RecallPhase.judge);
      expect(result.nodes, hasLength(1));
      expect(result.nodes.single.id, 'event-4');
    });

    test('PLAN 已消耗两次 POST 时不再调用 JUDGE', () async {
      var calls = 0;
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['钥匙'],
            ),
          ),
        ),
        currentInput: '钥匙',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          calls++;
          expect(requestBudget.tryConsumePost(), isTrue);
          expect(requestBudget.tryConsumePost(), isTrue);
          final alias = _catalogAlias(prompt, 'k', '钥匙');
          return jsonEncode(<String, dynamic>{
            'v': 1,
            'action': 'search',
            'k': <String>[alias],
            't': <String>[],
            'r': <String>[],
            'recency': 'any',
            'confidence': 'medium',
          });
        },
      );

      expect(calls, 1);
      expect(result.postCount, 2);
      expect(result.phase, RecallPhase.judgeFallback);
      expect(result.nodes, hasLength(5));
    });

    test('取消后阻止在途 PLAN 继续兼容端点 POST', () async {
      final cancelled = Completer<void>();
      var posts = 0;
      final recall = EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              keywords: const <String>['车站'],
            ),
          ),
        ),
        currentInput: '车站',
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        cancellation: cancelled.future,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          if (requestBudget.tryConsumePost()) posts++;
          cancelled.complete();
          await Future<void>.delayed(Duration.zero);
          if (requestBudget.tryConsumePost()) posts++;
          return '{}';
        },
      );

      await expectLater(recall, throwsA(isA<EventRecallCancelled>()));
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
    });

    test('JSON 转义膨胀后 PLAN 总输入仍不超过 3200 字符', () async {
      final controlHeavyInput =
          '悬疑${List<String>.filled(700, '\u0001x').join()}';
      final result = await EventRecallCoordinator().recall(
        graph: EventGraphMemory(
          longTermQueue: List<EventNode>.generate(
            6,
            (index) => _node(
              'event-$index',
              index,
              theme: const <String>['悬疑'],
            ),
          ),
        ),
        currentInput: controlHeavyInput,
        recentMessages: const <RecallDialogueMessage>[],
        hotNodeIds: const <String>{},
        mainProfile: _profile('main'),
        memoryRecallProfile: null,
        invokeModel: ({
          required prompt,
          required profile,
          required requestBudget,
        }) async {
          requestBudget.tryConsumePost();
          expect(prompt.runes.length, lessThanOrEqualTo(3200));
          return '{"v":1,"action":"skip","k":[],"t":[],"r":[],'
              '"recency":"any","confidence":"high"}';
        },
      );

      expect(result.postCount, 1);
    });
  });
}

LlmProfile _profile(String model) => LlmProfile(
      apiKey: 'key',
      model: model,
      parameters: const LlmParameters(maxTokens: 2048, timeoutSeconds: 60),
    );

EventNode _node(
  String id,
  int createdAtMs, {
  List<String> keywords = const <String>[],
  List<String> theme = const <String>[],
}) {
  return EventNode(
    id: id,
    tier: EventTier.longTerm,
    event: EventMemory(
      description: '描述 $id',
      keywords: keywords,
      theme: theme,
    ),
    createdAtMs: createdAtMs,
  );
}

String _catalogAlias(String prompt, String bucket, String value) {
  final payload = jsonDecode(prompt.substring(prompt.indexOf('DATA=') + 5))
      as Map<String, dynamic>;
  final catalog = payload['catalog'] as Map<String, dynamic>;
  final entries = catalog[bucket] as List<dynamic>;
  final entry = entries.cast<Map<String, dynamic>>().singleWhere(
        (item) => item['value'] == value,
      );
  return entry['id'] as String;
}
