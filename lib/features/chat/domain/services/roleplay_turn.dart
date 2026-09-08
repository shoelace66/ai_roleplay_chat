import '../../../../core/utils/roleplay_protocol.dart';
import '../../../../core/utils/structured_output_regex_parser.dart';
import '../../data/models/contact.dart';
import 'memory_patch_reducer.dart';

/// 只有完整、通过本地状态校验的一轮，才允许作为正文和记忆一起提交。
class RoleplayTurn {
  RoleplayTurn._(this.reply, this.patch, this.memory);

  final String reply;
  final Map<String, dynamic> patch;
  final MemoryPatchResult memory;

  factory RoleplayTurn.parse({
    required String raw,
    required Contact contact,
    required String userInput,
    required String initialContext,
    bool allowSummary = false,
  }) {
    final payload = StructuredOutputRegexParser.parsePrimaryPayload(raw);
    final reply = payload?['reply'];
    final patch = payload?['memoryPatch'];
    final version = payload?['protocolVersion'];
    if (reply is! String ||
        reply.trim().isEmpty ||
        (patch != null && patch is! Map<String, dynamic>) ||
        (version != null &&
            version != RoleplayProtocol.version &&
            version != 'roleplay-memory-v2' &&
            version != 'roleplay-memory-v3' &&
            version != 'roleplay-memory-v4')) {
      throw const FormatException('回复格式无效，本轮未提交状态；可手动重试');
    }
    if (version == RoleplayProtocol.version ||
        version == 'roleplay-memory-v4') {
      if (patch is Map && patch.containsKey('currentStates')) {
        throw const FormatException('请使用按ID校验的 stateTransition');
      }
      final brief = patch is Map ? patch['eventBrief'] : null;
      if (brief is! Map ||
          brief['description'] is! String ||
          (brief['description'] as String).trim().isEmpty) {
        throw const FormatException('回复缺少本轮事件，本轮未提交状态');
      }
    }
    final normalized = patch as Map<String, dynamic>? ?? <String, dynamic>{};
    final memory = const MemoryPatchReducer().reduce(
      contact: contact,
      patch: normalized,
      userInput: userInput,
      rawAiResponse: raw,
      initialContext: initialContext,
      allowSummary: allowSummary,
    );
    return RoleplayTurn._(reply.trim(), normalized, memory);
  }
}
