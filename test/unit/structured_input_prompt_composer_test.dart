import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/app_settings.dart';
import 'package:flutter_chat_demo/core/utils/structured_input_prompt_composer.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_chat_demo/features/worldbook/domain/entities/world_book.dart';

void main() {
  group('StructuredInputPromptComposer', () {
    test('结构化协议包含显式版本并位于 memoryPatch 之前', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeSystemPromptWithContactObject(
        basePrompt: '',
        contact: Contact(
          id: 'role-protocol',
          name: '测试角色',
          avatar: '',
          createdAt: DateTime(2026),
        ),
      );

      expect(result, contains('roleplay-memory-v5'));
      expect(
        result.indexOf('"protocolVersion"'),
        lessThan(result.indexOf('"memoryPatch"')),
      );
    });

    test('composeStructuredOutputPrompt 包含用户输入', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPrompt(
        userInput: '你好',
        outputSchema: '{"reply":"string"}',
      );

      expect(result, contains('你好'));
      expect(result, contains('【用户输入】'));
      expect(result, contains('【输出格式】'));
    });

    test('composeStructuredOutputPrompt 包含系统提示', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPrompt(
        userInput: 'test',
        systemPrompt: '你是一个助手',
        outputSchema: '{}',
      );

      expect(result, contains('你是一个助手'));
      expect(result, contains('【系统提示】'));
    });

    test('composeStructuredOutputPrompt 无系统提示时省略该段', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPrompt(
        userInput: 'test',
        outputSchema: '{}',
      );

      expect(result.contains('【系统提示】'), isFalse);
    });

    test('缓存友好请求把固定 system 与动态 user 严格分离', () {
      final composer = StructuredInputPromptComposer();
      final result = composer.composeStructuredOutputPromptParts(
        userInput: '继续推门',
        systemPrompt: '固定规则与角色设定',
        dynamicContext: '上一轮停在门已经推开一道缝',
        outputSchema: '{"reply":"string"}',
      );

      expect(result.systemPrompt, contains('固定规则与角色设定'));
      expect(result.systemPrompt, isNot(contains('门已经推开一道缝')));
      expect(result.systemPrompt, isNot(contains('继续推门')));
      expect(result.userPrompt, contains('门已经推开一道缝'));
      expect(result.userPrompt, endsWith('继续推门'));
    });

    test('composeStructuredOutputPrompt 使用自定义 settings', () {
      final composer = StructuredInputPromptComposer(
        settings: const AppSettings(maxPromptLineLength: 50),
      );
      final result = composer.composeStructuredOutputPrompt(
        userInput: 'test',
        outputSchema: '{}',
      );

      expect(result, isNotEmpty);
    });

    test('结构化输出把可见回复放在记忆补丁之前', () {
      const schema = ChatRepository.outputSchema;

      final memoryPatchIndex = schema.indexOf('"memoryPatch"');
      final summaryIndex = schema.indexOf('"summary"');
      final eventBriefIndex = schema.indexOf('"eventBrief"');
      final currentStatesIndex = schema.indexOf('"stateTransition"');
      final replyIndex = schema.indexOf('"reply"');

      expect(memoryPatchIndex, greaterThanOrEqualTo(0));
      expect(replyIndex, greaterThanOrEqualTo(0));
      expect(replyIndex, lessThan(memoryPatchIndex));
      expect(eventBriefIndex, greaterThan(memoryPatchIndex));
      expect(summaryIndex, greaterThan(eventBriefIndex));
      expect(currentStatesIndex, greaterThan(summaryIndex));
    });

    test('角色 Prompt 明确本轮事件先于正文且正文不得改写事件结果', () {
      final composer = StructuredInputPromptComposer();
      final prompt = composer.composeSystemPromptWithContactObject(
        basePrompt: '保持角色一致',
        contact: Contact(
          id: 'role-1',
          name: '林夏',
          avatar: '',
          createdAt: DateTime(2026),
        ),
      );

      expect(prompt, contains('eventBrief 每轮必须输出'));
      expect(prompt, contains('在组织内容时先确定 eventBrief 和 stateTransition'));
      expect(prompt,
          contains('序列化 JSON 时仍按 protocolVersion、reply、memoryPatch 的顺序'));
      expect(
        prompt.indexOf('"reply"'),
        lessThan(prompt.indexOf('"memoryPatch"')),
      );
      expect(prompt, contains('上一轮终点/连续性锚点'));
      expect(prompt, contains('已经开始或完成的动作不得退回'));
      expect(prompt, contains('上一段 reply 与本轮 reply 会被直接拼接'));
    });

    test('fixedInput 不再遮蔽结构化角色字段，世界书时间线进入稳定资料', () {
      final sections = StructuredInputPromptComposer()
          .composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持克制的文风',
        contact: Contact(
          id: 'role-full-profile',
          name: '林夏',
          avatar: '',
          fixedInput: '你是雨城侦探。',
          personality: const ['理性', '克制'],
          appearance: const ['短发', '黑色风衣'],
          personalInfo: const ['住在旧城区'],
          backgroundStory: const ['曾调查失踪案'],
          narrativeRules: const ['使用第一人称'],
          otherCharacteristics: const ['怕冷'],
          worldBook: const WorldBook(
            timelineEvents: [
              WorldTimelineEvent(
                id: 'timeline-1',
                title: '雨城停电',
                description: '全城停电一小时',
                year: 2025,
              ),
            ],
          ),
          createdAt: DateTime(2026),
        ),
      );

      expect(sections.cacheablePrefix, contains('你是雨城侦探'));
      expect(sections.cacheablePrefix, contains('理性'));
      expect(sections.cacheablePrefix, contains('黑色风衣'));
      expect(sections.cacheablePrefix, contains('曾调查失踪案'));
      expect(sections.cacheablePrefix, contains('使用第一人称'));
      expect(sections.cacheablePrefix, contains('timelineEvents'));
      expect(sections.cacheablePrefix, contains('雨城停电'));
      expect(sections.cacheablePrefix, contains('应用运行契约（最高优先级'));
      expect(sections.cacheablePrefix, endsWith('\n'));
    });

    test('所有模型记忆位于动态区，固定设定单独缓存', () {
      const ultra = EventNode(
        id: 'ultra-1',
        tier: EventTier.ultraLongTerm,
        event: EventMemory(description: '很久以前两人已经相识'),
        createdAtMs: 1,
      );
      const long = EventNode(
        id: 'long-1',
        tier: EventTier.longTerm,
        event: EventMemory(description: '两人抵达旧宅'),
        createdAtMs: 2,
      );
      const short = EventNode(
        id: 'short-1',
        tier: EventTier.shortTerm,
        event: EventMemory(description: '门已经被推开一道缝'),
        createdAtMs: 3,
      );
      final composer = StructuredInputPromptComposer();
      final sections = composer.composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持连续',
        contact: Contact(
          id: 'role-cache',
          name: '林夏',
          avatar: '',
          fixedInput: '固定角色设定',
          eventGraph: const EventGraphMemory(
            ultraLongTermQueue: <EventNode>[ultra],
            longTermQueue: <EventNode>[long],
            shortTermQueue: <EventNode>[short],
          ),
          createdAt: DateTime(2026),
        ),
        mustSummarize: true,
        pendingSummaryEvents: const <EventMemory>[
          EventMemory(description: '需要总结的旧事件'),
        ],
      );

      expect(sections.cacheablePrefix, contains('固定角色设定'));
      expect(sections.dynamicContext, contains('很久以前两人已经相识'));
      expect(sections.cacheablePrefix, isNot(contains('很久以前两人已经相识')));
      expect(sections.dynamicContext, contains('两人抵达旧宅'));
      expect(sections.cacheablePrefix, isNot(contains('两人抵达旧宅')));
      expect(sections.cacheablePrefix, isNot(contains('门已经被推开一道缝')));
      expect(
        sections.cacheablePrefix,
        isNot(contains('【强制】本轮必须输出 memoryPatch.summary。')),
      );
      expect(sections.dynamicContext, contains('门已经被推开一道缝'));
      expect(sections.dynamicContext, contains('[2] [active] [上一轮终点/连续性锚点]'));
      expect(sections.dynamicContext, contains('【强制】'));
      expect(sections.dynamicContext, contains('需要总结的旧事件'));

      final merged = sections.merged;
      expect(
        merged.indexOf('固定角色设定'),
        lessThan(merged.indexOf('门已经被推开一道缝')),
      );
    });

    test('连续两轮只更新短期事件时 system 缓存前缀保持完全一致', () {
      Contact contactWithShort(String id, String description) => Contact(
            id: 'role-cache-stable',
            name: '林夏',
            avatar: '',
            fixedInput: '固定角色设定',
            eventGraph: EventGraphMemory(
              longTermQueue: const <EventNode>[
                EventNode(
                  id: 'long-stable',
                  tier: EventTier.longTerm,
                  event: EventMemory(description: '两人已经抵达旧宅'),
                  createdAtMs: 1,
                ),
              ],
              shortTermQueue: <EventNode>[
                EventNode(
                  id: id,
                  tier: EventTier.shortTerm,
                  event: EventMemory(description: description),
                  createdAtMs: 2,
                ),
              ],
            ),
            createdAt: DateTime(2026),
          );

      final composer = StructuredInputPromptComposer();
      final first = composer.composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持连续',
        contact: contactWithShort('short-1', '手已经搭在门把上'),
      );
      final second = composer.composeSystemPromptSectionsWithContactObject(
        basePrompt: '保持连续',
        contact: contactWithShort('short-2', '门已经被推开一道缝'),
      );

      expect(first.cacheablePrefix, second.cacheablePrefix);
      expect(first.dynamicContext, isNot(second.dynamicContext));
    });

    test('详细状态不受通用列表条数和行长限制', () {
      final states = {for (var i = 0; i < 12; i++) '状态$i': '细节$i' * 30};
      final contact = Contact(
          id: 'detail',
          name: '林夏',
          avatar: '',
          currentStates: states,
          createdAt: DateTime(2026));
      final composer = StructuredInputPromptComposer(
          settings: const AppSettings(
              maxPromptListItems: 1, maxPromptLineLength: 50));
      final sections = composer.composeSystemPromptSectionsWithContactObject(
          basePrompt: '', contact: contact);
      for (final value in states.values) {
        expect(sections.dynamicContext, contains(value));
      }
    });

    test('知识和长期摘要改变不会改变完整system，协议只出现一次', () {
      final first = Contact(
          id: 'cache',
          name: '林夏',
          avatar: '',
          fixedInput: '固定设定',
          createdAt: DateTime(2026));
      final second = first.copyWith(
          worldKnowledge: WorldKnowledgeBucket(['新发现']),
          eventGraph: const EventGraphMemory(longTermQueue: [
            EventNode(
                id: 'new',
                tier: EventTier.longTerm,
                event: EventMemory(description: '新的长期摘要'),
                createdAtMs: 1),
          ]));
      final composer = StructuredInputPromptComposer();
      final a = composer.composeSystemPromptSectionsWithContactObject(
          basePrompt: '', contact: first);
      final b = composer.composeSystemPromptSectionsWithContactObject(
          basePrompt: '', contact: second);
      expect(a.cacheablePrefix, b.cacheablePrefix);
      expect(b.dynamicContext, contains('新发现'));
      expect(b.dynamicContext, contains('新的长期摘要'));
      expect(RegExp('"protocolVersion"').allMatches(b.cacheablePrefix),
          hasLength(1));
      expect(b.cacheablePrefix, isNot(contains('180字')));
      expect(b.cacheablePrefix, isNot(contains('所有指令均已载入')));
    });

    test('故事 Prompt 禁止 AI 擅自推动主线', () {
      final composer = StructuredInputPromptComposer();
      final prompt = composer.composeSystemPromptWithContactObject(
        basePrompt: '',
        contact: Contact(
          id: 'story-1',
          name: '雨夜',
          avatar: '',
          category: ContactCategory.story,
          createdAt: DateTime(2026),
        ),
      );

      expect(prompt, contains('不得擅自引入主要角色'));
      expect(prompt, contains('不得擅自引入主要角色、核心冲突、重大秘密、时间跳跃或场景切换'));
    });
  });
}
