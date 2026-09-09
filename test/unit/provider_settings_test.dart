import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';

void main() {
  group('LlmParameters', () {
    test('JSON 往返', () {
      const p = LlmParameters(
        temperature: 0.5,
        topP: 0.9,
        maxTokens: 1024,
        frequencyPenalty: 0.3,
        presencePenalty: -0.2,
        timeoutSeconds: 90,
        stream: true,
        useJsonResponseFormat: true,
      );
      final restored = LlmParameters.fromJson(p.toJson());
      expect(restored.temperature, 0.5);
      expect(restored.topP, 0.9);
      expect(restored.maxTokens, 1024);
      expect(restored.frequencyPenalty, 0.3);
      expect(restored.presencePenalty, -0.2);
      expect(restored.timeoutSeconds, 90);
      expect(restored.stream, isTrue);
      expect(restored.useJsonResponseFormat, isTrue);
    });
  });

  group('ProviderSettings', () {
    test('JSON 往返', () {
      const s = ProviderSettings(
        llm: LlmProfile(
          presetId: 'openai',
          apiKey: 'sk',
          baseUrl: 'https://x',
          model: 'gpt-4o',
          parameters: LlmParameters(temperature: 0.2),
          inputPricePerMillion: 1.5,
          outputPricePerMillion: 6,
        ),
        fallbackLlmProfiles: <LlmProfile>[
          LlmProfile(apiKey: 'fallback', model: 'fallback-model'),
        ],
        memoryRecallLlm: LlmProfile(
          presetId: 'openai',
          apiKey: 'recall-key',
          baseUrl: 'https://recall.example/v1',
          model: 'cheap-model',
          parameters: LlmParameters(
            temperature: 0,
            maxTokens: 128,
            timeoutSeconds: 12,
          ),
        ),
        image: ImageProfile(
          presetId: 'pollinations',
          baseUrl: 'https://x',
          model: 'flux',
        ),
        tts: TtsProfile(
          presetId: 'openai_tts',
          apiKey: 'sk',
          baseUrl: 'https://x',
          model: 'tts-1',
        ),
      );
      final restored = ProviderSettings.fromJson(s.toJson());
      expect(restored.llm.presetId, 'openai');
      expect(restored.llm.parameters.temperature, 0.2);
      expect(restored.llm.inputPricePerMillion, 1.5);
      expect(restored.llm.outputPricePerMillion, 6);
      expect(restored.fallbackLlmProfiles.single.model, 'fallback-model');
      expect(restored.memoryRecallLlm?.apiKey, 'recall-key');
      expect(restored.memoryRecallLlm?.model, 'cheap-model');
      expect(restored.memoryRecallLlm?.parameters.maxTokens, 128);
      expect(restored.image.presetId, 'pollinations');
      expect(restored.tts.presetId, 'openai_tts');
    });

    test('copyWith 可保留、替换和清除事件召回模型', () {
      const original = ProviderSettings(
        memoryRecallLlm: LlmProfile(apiKey: 'old', model: 'cheap-old'),
      );

      expect(original.copyWith().memoryRecallLlm?.model, 'cheap-old');
      expect(
        original
            .copyWith(
              memoryRecallLlm:
                  const LlmProfile(apiKey: 'new', model: 'cheap-new'),
            )
            .memoryRecallLlm
            ?.model,
        'cheap-new',
      );
      expect(
        original.copyWith(clearMemoryRecallLlm: true).memoryRecallLlm,
        isNull,
      );
    });
  });
}
