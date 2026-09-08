import '../../../../core/utils/structured_output_regex_parser.dart';
import '../../data/models/contact.dart';
import '../../data/models/continuity_state.dart';
import 'continuity_state_machine.dart';

enum BelongingChangeType { added, mentioned, removed }

class BelongingChange {
  const BelongingChange({required this.type, required this.name});

  final BelongingChangeType type;
  final String name;
}

class MemoryPatchResult {
  const MemoryPatchResult({
    this.summary,
    this.turnEvent,
    required this.worldKnowledge,
    required this.selfKnowledge,
    required this.userKnowledge,
    required this.status,
    required this.currentStates,
    required this.continuity,
    required this.belongingChanges,
    required this.belongings,
    required this.mood,
    required this.time,
  });

  final EventMemory? summary;
  final EventMemory? turnEvent;
  final List<String> worldKnowledge;
  final List<String> selfKnowledge;
  final List<String> userKnowledge;
  final List<String> status;
  final Map<String, String> currentStates;
  final ContinuityState continuity;
  final List<BelongingChange> belongingChanges;
  final List<String> belongings;
  final String mood;
  final String time;

  List<EventMemory> get events => <EventMemory>[
        if (summary != null) summary!,
        if (turnEvent != null) turnEvent!,
      ];
}

/// 将模型的 memoryPatch 归并为新的联系人投影。
///
/// 本服务不修改事件图、不持久化，也不依赖 Flutter，因此可以在提交事务前独立
/// 验证补丁。最低层的 [turnEvent] 来自 `eventBrief`，仍是正文前生成的规范事件。
class MemoryPatchReducer {
  const MemoryPatchReducer();

  MemoryPatchResult reduce({
    required Contact contact,
    required Map<String, dynamic> patch,
    required String userInput,
    required String rawAiResponse,
    String initialContext = '',
    bool allowSummary = true,
  }) {
    var transition = patch['stateTransition'];
    if (transition == null && patch['currentStates'] is Map) {
      final values = _readStateValues(patch['currentStates']);
      final changes = <Map<String, dynamic>>[];
      for (final d in contact.continuity.definitions) {
        if (values.containsKey(d.name)) {
          changes.add({
            'key': d.id,
            'from': contact.continuity.values[d.id] ?? d.initialValue,
            'to': values[d.name]
          });
        }
      }
      transition = {
        'baseRevision': contact.continuity.revision,
        'changes': changes
      };
    }
    final state = const ContinuityStateMachine()
        .apply(current: contact.continuity, transition: transition);
    final sourceDialog = _buildSourceDialog(userInput, rawAiResponse);
    final summary = allowSummary
        ? _readEvent(patch['summary'], sourceDialog: sourceDialog)
        : null;
    final turnEvent = _readEvent(
      patch['eventBrief'],
      sourceDialog: sourceDialog,
    );
    final belongingChanges = _readBelongingChanges(
      legacyValues:
          StructuredOutputRegexParser.extractStringList(patch, 'belongings'),
      structuredValues: patch['belongingChanges'],
    );

    return MemoryPatchResult(
      summary: summary,
      turnEvent: turnEvent,
      worldKnowledge: _applyKnowledgeChanges(
        contact.worldKnowledge.items,
        legacyAdds: StructuredOutputRegexParser.extractStringList(
            patch, 'worldKnowledge'),
        structuredValues: patch['knowledgeChanges'],
        scope: 'world',
      ),
      selfKnowledge: _applyKnowledgeChanges(
        contact.selfKnowledge.items,
        legacyAdds: StructuredOutputRegexParser.extractStringList(
            patch, 'selfKnowledge'),
        structuredValues: patch['knowledgeChanges'],
        scope: 'self',
      ),
      userKnowledge: _applyKnowledgeChanges(
        contact.userKnowledge.items,
        legacyAdds: StructuredOutputRegexParser.extractStringList(
            patch, 'userKnowledge'),
        structuredValues: patch['knowledgeChanges'],
        scope: 'user',
      ),
      status: _mergeUnique(
        contact.status,
        StructuredOutputRegexParser.extractStringList(patch, 'status'),
      ),
      currentStates: state.byName,
      continuity: state,
      belongingChanges: belongingChanges,
      belongings: _applyBelongingChanges(
        contact.belongings,
        belongingChanges,
      ),
      mood: StructuredOutputRegexParser.extractString(patch, 'mood') ??
          contact.mood,
      time: StructuredOutputRegexParser.extractString(patch, 'time') ??
          contact.time,
    );
  }

  EventMemory? _readEvent(dynamic value, {required String sourceDialog}) {
    if (value is! Map) return null;
    final normalized = value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
    final event = EventMemory.fromJson(normalized);
    if (event.isEmpty) return null;
    return EventMemory(
      description: event.description,
      keywords: event.keywords,
      theme: event.theme,
      sourceDialog: sourceDialog,
    );
  }

  String _buildSourceDialog(String userInput, String rawAiResponse) {
    final lines = <String>[];
    final normalizedInput = userInput.trim();
    if (normalizedInput.isNotEmpty) lines.add('用户：$normalizedInput');
    final normalizedResponse = rawAiResponse.trim();
    if (normalizedResponse.isNotEmpty) {
      final reply = StructuredOutputRegexParser.extractReply(rawAiResponse) ??
          normalizedResponse;
      lines.add('AI：$reply');
    }
    return lines.join('\n');
  }

  List<BelongingChange> _readBelongingChanges({
    required List<String> legacyValues,
    required dynamic structuredValues,
  }) {
    final result = <BelongingChange>[];
    final pattern = RegExp(r'^[\(（]\s*(新增|提及)\s*[\)）]\s*(.+)$');
    for (final value in legacyValues) {
      final match = pattern.firstMatch(value);
      final name = match?.group(2)?.trim() ?? '';
      if (match == null || name.isEmpty) continue;
      result.add(BelongingChange(
        type: match.group(1)?.trim() == '新增'
            ? BelongingChangeType.added
            : BelongingChangeType.mentioned,
        name: name,
      ));
    }
    if (structuredValues is List) {
      for (final raw in structuredValues) {
        if (raw is! Map) continue;
        final operation = (raw['operation'] ?? '').toString().trim();
        final item = (raw['item'] ?? '').toString().trim();
        if (item.isEmpty) continue;
        final type = switch (operation) {
          'add' => BelongingChangeType.added,
          'mention' => BelongingChangeType.mentioned,
          'remove' => BelongingChangeType.removed,
          _ => null,
        };
        if (type != null) result.add(BelongingChange(type: type, name: item));
      }
    }
    return result;
  }

  List<String> _applyBelongingChanges(
    List<String> current,
    List<BelongingChange> changes,
  ) {
    final result = <String>[...current];
    for (final change in changes) {
      result.removeWhere((item) => item == change.name);
      if (change.type != BelongingChangeType.removed) {
        result.add(change.name);
      }
    }
    return result;
  }

  List<String> _applyKnowledgeChanges(
    List<String> current, {
    required List<String> legacyAdds,
    required dynamic structuredValues,
    required String scope,
  }) {
    final result = _mergeUnique(current, legacyAdds);
    if (structuredValues is! List) return result;
    for (final raw in structuredValues) {
      if (raw is! Map || raw['scope']?.toString().trim() != scope) continue;
      final operation = (raw['operation'] ?? '').toString().trim();
      final from = (raw['from'] ?? '').toString().trim();
      final to = (raw['to'] ?? '').toString().trim();
      switch (operation) {
        case 'add':
          if (to.isNotEmpty && !result.contains(to)) result.add(to);
          break;
        case 'remove':
          if (from.isNotEmpty) result.removeWhere((item) => item == from);
          break;
        case 'replace':
          if (from.isEmpty || to.isEmpty) break;
          final index = result.indexOf(from);
          if (index < 0) break;
          result[index] = to;
          final first = result.indexOf(to);
          for (var i = result.length - 1; i > first; i--) {
            if (result[i] == to) result.removeAt(i);
          }
          break;
      }
    }
    return result;
  }

  Map<String, String> _readStateValues(dynamic value) => value is Map
      ? <String, String>{
          for (final entry in value.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        }
      : const <String, String>{};

  List<String> _mergeUnique(List<String> current, List<String> patch) {
    final result = <String>[];
    final seen = <String>{};
    for (final item in current.followedBy(patch)) {
      final normalized = item.trim();
      if (normalized.isNotEmpty && seen.add(normalized)) result.add(normalized);
    }
    return result;
  }
}
