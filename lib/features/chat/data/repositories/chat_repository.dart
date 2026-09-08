import '../../../../core/utils/roleplay_protocol.dart';
import '../../../../core/data/models/app_settings.dart';
import '../../../../core/data/models/provider_settings.dart';
import '../../../../core/utils/structured_input_prompt_composer.dart';
import '../../../../infrastructure/services/ai_service.dart';
import '../models/message.dart';

class ChatRepository {
  ChatRepository({required AiService aiService}) : _aiService = aiService;

  AiService get aiService => _aiService;

  static const String outputSchema = RoleplayProtocol.outputSchema;

  final AiService _aiService;
  Future<Message> askAi({
    required String contactId,
    required String contactName,
    required Message userMessage,
    String? systemPrompt,
    String? dynamicContext,
    List<Message> conversationHistory = const <Message>[],
    AppSettings? settings,
    LlmProfile? profile,
  }) async {
    final composer = StructuredInputPromptComposer(
      settings: settings ?? const AppSettings(),
    );
    final promptParts = composer.composeStructuredOutputPromptParts(
      userInput: userMessage.content,
      systemPrompt: systemPrompt,
      dynamicContext: dynamicContext,
      outputSchema: systemPrompt?.trim().isNotEmpty == true ? '' : outputSchema,
    );

    final assistantReply = await _aiService.ask(
      promptParts.userPrompt,
      contactId: contactId,
      contactName: contactName,
      systemPrompt: promptParts.systemPrompt,
      history: _toAiHistory(conversationHistory),
      requireJsonObject: true,
      profile: profile,
    );

    final assistantMessage = Message(
      id: 'assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: assistantReply,
      createdAt: DateTime.now(),
    );
    return assistantMessage;
  }

  Stream<String> askAiStream({
    required String contactId,
    required String contactName,
    required Message userMessage,
    String? systemPrompt,
    String? dynamicContext,
    List<Message> conversationHistory = const <Message>[],
    AppSettings? settings,
    LlmProfile? profile,
  }) {
    final composer = StructuredInputPromptComposer(
      settings: settings ?? const AppSettings(),
    );
    final promptParts = composer.composeStructuredOutputPromptParts(
      userInput: userMessage.content,
      systemPrompt: systemPrompt,
      dynamicContext: dynamicContext,
      outputSchema: systemPrompt?.trim().isNotEmpty == true ? '' : outputSchema,
    );
    return _aiService.askStream(
      promptParts.userPrompt,
      contactId: contactId,
      contactName: contactName,
      systemPrompt: promptParts.systemPrompt,
      history: _toAiHistory(conversationHistory),
      requireJsonObject: true,
      profile: profile,
    );
  }

  Future<String> askUtility({
    required String contactId,
    required String contactName,
    required String prompt,
    LlmProfile? profile,
    RecallRequestBudget? requestBudget,
  }) {
    return _aiService.ask(
      prompt,
      contactId: contactId,
      contactName: contactName,
      profile: profile,
      requestBudget: requestBudget,
    );
  }

  List<AiChatMessage> _toAiHistory(List<Message> messages) => messages
      .where((message) =>
          message.status == MessageStatus.sent &&
          !message.isImageMessage &&
          message.content.trim().isNotEmpty)
      .map(
        (message) => AiChatMessage(
          role: message.role.name,
          content: message.content,
        ),
      )
      .toList(growable: false);
}
