import '../../domain/services/ai_service.dart';
import '../../domain/structured/structured_input_prompt_composer.dart';
import '../models/message.dart';

class ChatRepository {
  ChatRepository({required AiService aiService}) : _aiService = aiService;

  static const String _outputSchema = '''
{
  "reply": "给用户的回复",
  "memoryPatch": {
    "worldKnowledge": ["新增的世界观知识，无则[]"],
    "selfKnowledge": ["新增的自我认知，无则[]"],
    "userKnowledge": ["新增的对用户了解，无则[]"],
    "events": [{
      "time": "",
      "location": "",
      "characters": "",
      "cause": "",
      "process": "",
      "result": "",
      "attitude": ""
    }],
    "belongings": ["(新增)手电筒","(提及)地图，无则[]"],
    "status": ["状态变化，无则[]"],
    "mood": "当前情绪，无则空字符串",
    "time": "当前时间，无则空字符串"
  }
}
''';

  final AiService _aiService;
  final Map<String, List<Message>> _cacheByContact = <String, List<Message>>{};

  List<Message> getCachedMessages(String contactId) {
    final list = _cacheByContact[contactId] ?? const <Message>[];
    return List<Message>.unmodifiable(list);
  }

  Future<Message> askAi({
    required String contactId,
    required String contactName,
    required Message userMessage,
    String? systemPrompt,
  }) async {
    final list = _cacheByContact.putIfAbsent(contactId, () => <Message>[]);
    list.add(userMessage);

    final mergedPrompt =
        StructuredInputPromptComposer.composeStructuredOutputPrompt(
      userInput: userMessage.content,
      systemPrompt: systemPrompt,
      outputSchema: _outputSchema,
    );

    final assistantReply = await _aiService.ask(
      mergedPrompt,
      contactId: contactId,
      contactName: contactName,
    );

    final assistantMessage = Message(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: assistantReply,
      createdAt: DateTime.now(),
    );
    list.add(assistantMessage);
    return assistantMessage;
  }

  Future<String> askUtility({
    required String contactId,
    required String contactName,
    required String prompt,
  }) {
    return _aiService.ask(
      prompt,
      contactId: contactId,
      contactName: contactName,
    );
  }
}
