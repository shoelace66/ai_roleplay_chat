import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';

/// 用 utf8 编码构造 Response。
///
/// 注意：必须用 [http.Response.bytes] + 小写 `content-type` 头，
/// 否则 `http.Response` 构造器会用 latin1 重新编码 body，
/// 而读取时又用 utf8 解码（json 类型的默认行为），
/// 导致中文字符被错误转码。
http.Response _utf8Response(String body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

/// Round-trip 测试：用 [MockClient] 拦截 HTTP 请求，
/// 验证 AiService 发出的 URL / method / headers / body 完全对齐 OpenAI 协议，
/// 同时验证响应解析在各种 edge case 下也正确。
void main() {
  group('AiService 请求 / 响应格式（OpenAI 协议对齐）', () {
    test('正确构造 chat/completions 请求体（含 temperature/top_p/penalty/max_tokens）',
        () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return _utf8Response(jsonEncode(<String, dynamic>{
          'id': 'chatcmpl-1',
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'index': 0,
              'message': <String, dynamic>{
                'role': 'assistant',
                'content': '你好'
              },
              'finish_reason': 'stop',
            },
          ],
        }));
      });

      final service = AiService(client: mock);
      final reply = await service.ask(
        'hello',
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          presetId: 'openai',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          parameters: LlmParameters(
            temperature: 0.3,
            topP: 0.9,
            maxTokens: 512,
            frequencyPenalty: 0.5,
            presencePenalty: -0.2,
            timeoutSeconds: 30,
            stream: false,
          ),
        ),
      );

      // 1. URL
      expect(captured.url.toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(captured.method, 'POST');

      // 2. Headers
      expect(captured.headers['Content-Type'], contains('application/json'));
      expect(captured.headers['Authorization'], 'Bearer sk-test');

      // 3. Body
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');
      expect(body['temperature'], 0.3);
      expect(body['top_p'], 0.9);
      expect(body['max_tokens'], 512);
      expect(body['frequency_penalty'], 0.5);
      expect(body['presence_penalty'], -0.2);
      expect(body['stream'], false);
      final messages = body['messages'] as List;
      expect(messages.length, 1);
      expect(messages.first['role'], 'user');
      expect(messages.first['content'], 'hello');

      // 4. 响应解析
      expect(reply, '你好');
    });

    test('角色请求保留原生历史角色，并按 Profile 选择 JSON 响应模式', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return _utf8Response(jsonEncode(<String, dynamic>{
          'choices': <Map<String, dynamic>>[
            <String, dynamic>{
              'message': <String, dynamic>{'content': '{"reply":"ok"}'},
            },
          ],
        }));
      });

      await AiService(client: mock).ask(
        '当前上下文与输入',
        systemPrompt: '稳定 Agent 契约',
        history: const <AiChatMessage>[
          AiChatMessage(role: 'user', content: '上一轮问题'),
          AiChatMessage(role: 'assistant', content: '上一轮回答'),
        ],
        requireJsonObject: true,
        contactId: 'c1',
        contactName: 'Test',
        profile: const LlmProfile(
          apiKey: 'sk',
          baseUrl: 'https://example.com/v1',
          model: 'm',
          parameters: LlmParameters(useJsonResponseFormat: true),
        ),
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['messages'], [
        {'role': 'system', 'content': '稳定 Agent 契约'},
        {'role': 'user', 'content': '上一轮问题'},
        {'role': 'assistant', 'content': '上一轮回答'},
        {'role': 'user', 'content': '当前上下文与输入'},
      ]);
    });

    test('兼容端点探测不能突破召回请求预算', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        return _utf8Response('not found', status: 404);
      });
      final service = AiService(client: mock);
      final budget = RecallRequestBudget(maxPosts: 1);

      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
          requestBudget: budget,
        ),
        throwsA(
          isA<AiServiceException>().having(
            (error) => error.userMessage,
            'userMessage',
            contains('预算已耗尽'),
          ),
        ),
      );
      expect(attempts, 1);
      expect(budget.consumed, 1);
      expect(budget.remaining, 0);
    });

    test('召回 POST 禁止客户端静默跟随重定向', () async {
      var attempts = 0;
      final mock = MockClient((request) async {
        attempts++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          'redirect',
          307,
          headers: const <String, String>{
            'location': 'https://example.com/redirected',
          },
        );
      });
      final service = AiService(client: mock);
      final budget = RecallRequestBudget(maxPosts: 2);

      await expectLater(
        service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
          requestBudget: budget,
        ),
        throwsA(isA<AiServiceException>()),
      );
      expect(attempts, 1);
      expect(budget.consumed, 1);
    });

    test('401 错误映射为清晰的提示', () async {
      final mock = MockClient((request) async {
        return _utf8Response('unauthorized', status: 401);
      });

      final service = AiService(client: mock);
      try {
        await service.ask(
          'hi',
          contactId: 'c1',
          contactName: 'Test',
          profile: const LlmProfile(
            apiKey: 'sk',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
        );
        fail('应该抛 AiServiceException');
      } on AiServiceException catch (e) {
        expect(e.userMessage, contains('API Key'));
        expect(e.userMessage, contains('401'));
      }
    });
  });

  group('SSE 流式响应（服务端不听话忽略 stream: false）', () {
    test('askStream 按 OpenAI SSE delta 顺序产出文本并强制 stream=true', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });
      final chunks = await AiService(client: mock)
          .askStream(
            'hi',
            systemPrompt: 'stable',
            contactId: 'c1',
            contactName: 'Test',
            profile: const LlmProfile(
              apiKey: 'sk',
              baseUrl: 'https://example.com/v1',
              model: 'm',
            ),
          )
          .toList();

      expect(chunks, ['你', '好']);
      expect(captured.headers['Accept'], 'text/event-stream');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      final messages = body['messages'] as List;
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], 'stable');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], 'hi');

      // A valid-looking prefix is not a successful transaction when the
      // provider explicitly reports truncation. Check both request paths.
      for (final useStream in [false, true]) {
        for (final sse in [false, true]) {
          final payload = jsonEncode({
            'choices': [
              {
                if (sse) 'delta': {'content': '{"reply":"partial"}'},
                if (!sse) 'message': {'content': '{"reply":"partial"}'},
                'finish_reason': 'length',
              }
            ]
          });
          final client = MockClient((_) async => _utf8Response(
              sse ? 'data: $payload\n\ndata: [DONE]\n\n' : payload));
          addTearDown(client.close);
          final service = AiService(client: client);
          const profile = LlmProfile(
              apiKey: 'test', baseUrl: 'https://example.com', model: 'm');
          final result = useStream
              ? service
                  .askStream('hi',
                      contactId: 'c1', contactName: 'Test', profile: profile)
                  .toList()
              : service.ask('hi',
                  contactId: 'c1', contactName: 'Test', profile: profile);
          await expectLater(
              result,
              throwsA(isA<AiServiceException>()
                  .having((e) => e.userMessage, 'message', contains('输出上限'))));
        }
      }
    });
  });
}
