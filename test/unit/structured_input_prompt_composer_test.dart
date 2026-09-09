import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/utils/structured_input_prompt_composer.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/worldbook/domain/entities/world_book.dart';

void main() {
  group('StructuredInputPromptComposer', () {
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
