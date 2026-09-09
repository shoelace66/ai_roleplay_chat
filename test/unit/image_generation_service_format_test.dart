import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/infrastructure/services/image_generation_service.dart';

void main() {
  group('ImageGenerationService 传参 / 响应格式', () {
    setUp(() {
      // 清理单例 profile，避免被前面的测试污染
      ImageGenerationService.instance.updateProfile(const ImageProfile());
    });

    test('OpenAI Images：POST {baseUrl}/images/generations + 正确请求体', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{
            'created': 1700000000,
            'data': <Map<String, dynamic>>[
              <String, dynamic>{'url': 'https://example.com/img.png'},
            ],
          })),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      ImageGenerationService.instance.debugSetHttpClient(mock);

      ImageGenerationService.instance.updateProfile(
        const ImageProfile(
          presetId: 'openai_image',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
          model: 'dall-e-3',
          parameters: ImageParameters(
            size: '1024x1024',
            n: 1,
            style: 'vivid',
            quality: 'hd',
            responseFormat: 'url',
            timeoutSeconds: 60,
          ),
        ),
      );

      final result = await ImageGenerationService.instance.generate(
        prompt: '夕阳下的城市',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(),
          'https://api.openai.com/v1/images/generations');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      expect(captured.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'dall-e-3');
      expect(body['prompt'], '夕阳下的城市');
      expect(body['n'], 1);
      expect(body['size'], '1024x1024');
      expect(body['style'], 'vivid');
      expect(body['quality'], 'hd');
      expect(body['response_format'], 'url');

      expect(result.success, isTrue);
      expect(result.imageUrl, 'https://example.com/img.png');
      expect(result.imageBytes, isNull);
    });
  });
}
