import 'dart:convert';

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
    Never invalid(String reason) =>
        throw FormatException('回复格式无效：$reason。本轮未提交状态；可手动重试。', raw);
    if (payload == null) {
      if (raw.trim().isEmpty) invalid('模型返回空白内容');
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException catch (error) {
        final offset = (error.offset ?? 0).clamp(0, raw.length);
        final prefix = raw.substring(0, offset);
        final line = '\n'.allMatches(prefix).length + 1;
        final column = offset - prefix.lastIndexOf('\n');
        final rune =
            offset < raw.length ? raw.substring(offset).runes.first : null;
        final character = offset == raw.length
            ? '文本末尾（JSON 可能被截断）'
            : '${jsonEncode(String.fromCharCode(rune!))} '
                '(U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')})';
        invalid('JSON 无法解析，第 $line 行第 $column 列，字符 $character');
      }
      invalid('顶层应为 JSON 对象，实际为 ${decoded.runtimeType}');
    }
    final reply = payload['reply'];
    final patch = payload['memoryPatch'];
    final version = payload['protocolVersion'];
    if (reply is! String) invalid(r'$.reply 缺失或不是字符串');
    if (reply.trim().isEmpty) invalid(r'$.reply 是空白字符串');
    if (patch != null && patch is! Map<String, dynamic>) {
      invalid(r'$.memoryPatch 应为对象，实际为 ' '${patch.runtimeType}');
    }
    if (version != null &&
        version != RoleplayProtocol.version &&
        version != 'roleplay-memory-v2' &&
        version != 'roleplay-memory-v3' &&
        version != 'roleplay-memory-v4') {
      invalid(r'$.protocolVersion 不受支持：'
          '${jsonEncode(version)}；应为 ${RoleplayProtocol.version}');
    }
    if (version == RoleplayProtocol.version ||
        version == 'roleplay-memory-v4') {
      if (patch is Map && patch.containsKey('currentStates')) {
        invalid(r'$.memoryPatch.currentStates 已停用，请使用按ID校验的 stateTransition');
      }
      final brief = patch is Map ? patch['eventBrief'] : null;
      if (brief is! Map ||
          brief['description'] is! String ||
          (brief['description'] as String).trim().isEmpty) {
        invalid(r'$.memoryPatch.eventBrief.description 缺失或不是非空字符串');
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
