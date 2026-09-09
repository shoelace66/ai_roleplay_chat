import 'dart:io';

import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/roleplay_turn.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in real test for the low-cost Ark Responses model.
///
/// PowerShell:
///   $env:ARK_API_KEY = Read-Host 'ARK_API_KEY'
///   flutter test tool/ark_responses_live_eval_test.dart --no-pub --reporter expanded
///
/// The key is read only from the current process and never written to a file.
void main() {
  test('Ark Responses 多轮图文输入输出完整链路', () async {
    final key = Platform.environment['ARK_API_KEY']?.trim() ?? '';
    if (key.isEmpty) throw StateError('需要 ARK_API_KEY；未发起真实调用');

    final repository = ChatRepository(aiService: AiService());
    var contact = Contact(
      id: 'ark-live',
      name: 'Ark Responses 测试',
      avatar: '',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final history = <Message>[];
    final prompts = <String>[
      '只根据图片回答：图中列出了哪些模型？',
      '只根据图片回答：Doubao-Seed-1.8 支持哪些输入？',
      '只根据图片回答：DeepSeek-V3.2 支持哪些输入和输出？',
      '只根据图片回答：GLM-4.7 支持哪些输入和输出？',
      '只根据图片回答：哪些模型支持图片输入？',
      '只根据图片回答：哪些模型支持视频输入？',
      '只根据图片回答：Doubao-Seed-1.8 支持文本输出吗？',
      '只根据图片回答：DeepSeek-V3.2 支持图片输入吗？',
      '只根据图片回答：GLM-4.7 支持视频输入吗？',
      '请复述图片中的模型输入输出对比，不要引入图片之外的信息。',
      '再次回答图片中 Doubao-Seed-1.8 的输入能力。',
      '再次回答图片中 DeepSeek-V3.2 的输入输出能力。',
      '再次回答图片中 GLM-4.7 的输入输出能力。',
      '图片中的表格是否涉及文本、图片和视频？请简答。',
      '图片中的表格是否说明了视频输出？请只依据图片回答。',
      '图片中的表格是否说明了图片输出？请只依据图片回答。',
      '请列出图片中仍然可以确认的两个事实。',
      '请用一句话总结图片中的模型能力对比。',
      '请检查你前面的回答是否一直围绕图片内容。只回答是或否并说明原因。',
      '最后复述图片中最关键的一条输入输出信息。',
    ];
    final expectedAnchors = <List<String>>[
      ['doubao', 'deepseek', 'glm'],
      ['文本', '图片', '视频'],
      ['deepseek', '文本'],
      ['glm', '文本'],
      ['doubao', '图片'],
      ['doubao', '视频'],
      ['doubao', '文本'],
      ['deepseek', '图片'],
      ['glm', '视频'],
      ['doubao', 'deepseek', 'glm'],
      ['doubao', '文本'],
      ['deepseek', '文本'],
      ['glm', '文本'],
      ['文本', '图片', '视频'],
      ['是', '否', '未说明'],
      ['是', '否', '未说明'],
      ['doubao', 'deepseek', 'glm'],
      ['doubao', 'deepseek', 'glm'],
      ['图片', '模型'],
      ['doubao', 'deepseek', 'glm'],
    ];
    final replies = <String>[];
    final anchorCoverage = <int>[];
    final failures = <String>[];
    var processed = 0;
    for (var index = 0; index < prompts.length; index++) {
      processed++;
      final userMessage = Message(
        id: 'ark-live-user-$index',
        role: MessageRole.user,
        content: prompts[index],
        createdAt: DateTime.utc(2026, 1, 1, 0, index),
      );
      late Message result;
      try {
        result = await repository.askAi(
          contactId: 'ark-live',
          contactName: 'Ark Responses 测试',
          userMessage: userMessage,
          conversationHistory: history.length > 8
              ? history.sublist(history.length - 8)
              : history,
          imageUrls: index == 0
              ? const <String>[
                  'https://ark-project.tos-cn-beijing.volces.com/doc_image/ark_demo_img_1.png',
                ]
              : const <String>[],
          profile: LlmProfile(
            presetId: 'doubao',
            apiKey: key,
            baseUrl: 'https://ark.cn-beijing.volces.com/api/v3/responses',
            model: 'doubao-seed-2-0-mini-260428',
            parameters: const LlmParameters(
              temperature: 0,
              maxTokens: 2048,
              timeoutSeconds: 90,
              stream: false,
              useJsonResponseFormat: false,
            ),
          ),
        );
      } on AiServiceException catch (error) {
        final detail = 'round=${index + 1} API failure: ${error.userMessage}';
        failures.add(detail);
        stdout.writeln('Ark Responses round ${index + 1}/20 FAIL: $detail');
        continue;
      }
      if (result.content.trim().isEmpty) {
        failures.add('round=${index + 1} empty response');
        stdout.writeln(
            'Ark Responses round ${index + 1}/20 FAIL: empty response');
        continue;
      }
      late RoleplayTurn turn;
      try {
        turn = RoleplayTurn.parse(
          raw: result.content,
          contact: contact,
          userInput: prompts[index],
          initialContext: 'Responses 图文输入测试；第 ${index + 1} 轮',
        );
      } on FormatException catch (error) {
        final detail = 'round=${index + 1} parse failure: ${error.message}';
        failures.add(detail);
        stdout.writeln('Ark Responses round ${index + 1}/20 FAIL: $detail');
        continue;
      }
      if (turn.reply.trim().isEmpty) {
        failures.add('round=${index + 1} empty reply');
        stdout.writeln('Ark Responses round ${index + 1}/20 FAIL: empty reply');
        continue;
      }
      replies.add(turn.reply.trim());
      final hits = expectedAnchors[index]
          .where((anchor) =>
              turn.reply.toLowerCase().contains(anchor.toLowerCase()))
          .toList(growable: false);
      if (hits.isEmpty) {
        final detail = 'round=${index + 1} semantic drift: ${turn.reply}';
        failures.add(detail);
        stdout.writeln('Ark Responses round ${index + 1}/20 DRIFT: $detail');
      }
      anchorCoverage.add(hits.length);
      contact = contact.copyWith(continuity: turn.memory.continuity);
      history
        ..add(userMessage)
        ..add(Message(
          id: 'ark-live-assistant-$index',
          role: MessageRole.assistant,
          // ChatProvider stores the validated display reply. This mirrors the
          // production history path; Repository wraps assistant history as a
          // JSON reply object on the next request.
          content: turn.reply,
          createdAt: DateTime.utc(2026, 1, 1, 0, index),
        ));
      final status = hits.isEmpty ? 'DRIFT' : 'PASS';
      stdout.writeln(
          'Ark Responses round ${index + 1}/20 $status anchors=${hits.length}: ${turn.reply}');
    }
    expect(processed, 20);
    expect(anchorCoverage.length, replies.length);
    expect(history.length, replies.length * 2);
    stdout.writeln(
        'Ark Responses summary: completed=20 pass=${replies.length} failures=${failures.length}');
    for (final failure in failures) {
      stdout.writeln('Ark Responses finding: $failure');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
