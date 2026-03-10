import 'dart:convert';

class StructuredOutputRegexParser {
  StructuredOutputRegexParser._();

  static final RegExp _jsonFence = RegExp(
    r'```json\s*([\s\S]*?)```',
    caseSensitive: false,
  );

  static String? extractPrimaryPayload(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final fenced = _jsonFence.firstMatch(text)?.group(1)?.trim();
    if (fenced != null && _isJsonObject(fenced)) {
      return fenced;
    }

    if (_isJsonObject(text)) {
      return text;
    }

    return _extractBestEffortJsonObject(text);
  }

  static Map<String, dynamic>? parsePrimaryPayload(String raw) {
    final payload = extractPrimaryPayload(raw);
    if (payload == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? extractReply(String raw) {
    final parsed = parsePrimaryPayload(raw);
    final reply = parsed?['reply']?.toString().trim();
    if (reply == null || reply.isEmpty) return null;
    return reply;
  }

  static Map<String, dynamic>? extractMemoryPatch(String raw) {
    final parsed = parsePrimaryPayload(raw);
    final patch = parsed?['memoryPatch'];
    if (patch is Map<String, dynamic>) return patch;
    return null;
  }

  static bool _isJsonObject(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  static String? _extractBestEffortJsonObject(String text) {
    final starts = <int>[];
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 123) {
        // {
        starts.add(i);
      }
    }

    for (final start in starts) {
      for (int end = text.length - 1; end > start; end--) {
        if (text.codeUnitAt(end) != 125) continue; // }
        final candidate = text.substring(start, end + 1).trim();
        if (_isJsonObject(candidate)) return candidate;
      }
    }
    return null;
  }
}
