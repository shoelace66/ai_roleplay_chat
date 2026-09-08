import '../../data/models/continuity_state.dart';
import 'dart:convert';

import '../../data/models/contact.dart';
import 'contact_json_normalizer.dart';

export 'contact_json_normalizer.dart' show ContactImportIssue;

class ContactImportResult {
  const ContactImportResult(
      {this.data, this.normalizedJson, this.issues = const []});
  final ContactImportData? data;
  final String? normalizedJson;
  final List<ContactImportIssue> issues;
  bool get isSuccess => data != null;
  List<ContactImportIssue> get errors =>
      issues.where((issue) => issue.isError).toList();
  String get errorMessage =>
      errors.map((issue) => issue.description).join('\n');
}

class ContactImportFallback {
  const ContactImportFallback({
    this.name = '',
    this.avatar = '',
    this.fixedInput = '',
    this.currentStates = const <String, String>{},
    this.voice = '',
    this.continuity = const ContinuityState.empty(),
  });

  final ContinuityState continuity;
  final String name;
  final String avatar;
  final String fixedInput;
  final Map<String, String> currentStates;
  final String voice;
}

class ContactImportData {
  const ContactImportData({
    required this.requestedId,
    this.continuity = const ContinuityState.empty(),
    required this.name,
    required this.avatar,
    required this.fixedInput,
    required this.currentStates,
    required this.personality,
    required this.appearance,
    required this.personalInfo,
    required this.settings,
    required this.backgroundStory,
    required this.narrativeRules,
    required this.otherCharacteristics,
    required this.worldKnowledge,
    required this.selfKnowledge,
    required this.userKnowledge,
    required this.belongings,
    required this.status,
    required this.mood,
    required this.time,
    required this.voice,
  });

  final ContinuityState continuity;
  final String requestedId;
  final String name;
  final String avatar;
  final String fixedInput;
  final Map<String, String> currentStates;
  final List<String> personality;
  final List<String> appearance;
  final List<String> personalInfo;
  final List<Map<String, dynamic>> settings;
  final List<String> backgroundStory;
  final List<String> narrativeRules;
  final List<String> otherCharacteristics;
  final List<String> worldKnowledge;
  final List<String> selfKnowledge;
  final List<String> userKnowledge;
  final List<String> belongings;
  final List<String> status;
  final String mood;
  final String time;
  final String voice;

  Contact toContact({
    required String id,
    required ContactCategory category,
    required List<String> keywordLibrary,
    required DateTime createdAt,
  }) {
    return Contact(
      id: id,
      name: name,
      avatar: avatar,
      category: category,
      fixedInput: fixedInput,
      currentStates: currentStates,
      continuity: continuity,
      personality: personality,
      appearance: appearance,
      personalInfo: personalInfo,
      settings: settings,
      backgroundStory: backgroundStory,
      narrativeRules: narrativeRules,
      otherCharacteristics: otherCharacteristics,
      worldKnowledge: WorldKnowledgeBucket(worldKnowledge),
      selfKnowledge: SelfKnowledgeBucket(selfKnowledge),
      userKnowledge: UserKnowledgeBucket(userKnowledge),
      keywordLibrary: keywordLibrary,
      belongings: belongings,
      status: status,
      mood: mood,
      time: time,
      voice: voice,
      createdAt: createdAt,
    );
  }
}

/// 联系人 JSON 的兼容解析器。
///
/// 只负责校验、规范化和后备字段合并；ID 冲突与持久化仍由应用层处理。
class ContactImportParser {
  const ContactImportParser();

  ContactImportData? parse(
    String source, {
    ContactImportFallback fallback = const ContactImportFallback(),
  }) =>
      parseDetailed(source, fallback: fallback).data;

  ContactImportResult parseDetailed(
    String source, {
    ContactImportFallback fallback = const ContactImportFallback(),
  }) {
    final normalized = ContactJsonNormalizer().normalize(source);
    final issues = [...normalized.issues];
    final json = normalized.json;
    if (json == null) return ContactImportResult(issues: issues);
    final name = _preferText(json['name'], fallback.name);
    if (name.isEmpty) {
      issues.add(const ContactImportIssue(
          r'$.name', '缺少名称。请填写 name（也支持“名称”“角色名称”“故事名称”），或在表单填写名称。',
          isError: true));
    }
    if (issues.any((issue) => issue.isError)) {
      return ContactImportResult(issues: issues);
    }
    try {
      final parsedStates = _stringMap(json['currentStates']);

      var configured = json['continuity'] != null
          ? ContinuityState.fromJson(json['continuity'])
          : fallback.continuity;
      final canonical = json['continuity'] is Map &&
          (json['continuity'] as Map)['definitions'] != null;
      if (!canonical) {
        configured = configured.withLegacy(parsedStates.isNotEmpty
            ? parsedStates
            : _normalizeMap(fallback.currentStates));
      }
      final data = ContactImportData(
        continuity: configured,
        requestedId: _text(json['id']),
        name: name,
        avatar: _preferText(json['avatar'], fallback.avatar),
        fixedInput: _preferText(json['fixedInput'], fallback.fixedInput),
        currentStates: configured.byName,
        personality: _stringList(json['personality']),
        appearance: _stringList(json['appearance']),
        personalInfo: _stringList(json['personalInfo']),
        settings: _settings(json['settings']),
        backgroundStory: _stringList(json['backgroundStory']),
        narrativeRules: _stringList(json['narrativeRules']),
        otherCharacteristics: _stringList(json['otherCharacteristics']),
        worldKnowledge: _stringList(json['worldKnowledge']),
        selfKnowledge: _stringList(json['selfKnowledge']),
        userKnowledge: _stringList(json['userKnowledge']),
        belongings: _stringList(json['belongings']),
        status: _stringList(json['status']),
        mood: _text(json['mood']),
        time: _text(json['time']),
        voice: _preferText(json['voice'], fallback.voice),
      );
      return ContactImportResult(
        data: data,
        normalizedJson: const JsonEncoder.withIndent('  ').convert(json),
        issues: issues,
      );
    } on FormatException catch (error) {
      return ContactImportResult(issues: [
        ...issues,
        ContactImportIssue(r'$.continuity', error.message, isError: true),
      ]);
    }
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _preferText(dynamic value, String fallback) {
    final parsed = _text(value);
    return parsed.isNotEmpty ? parsed : fallback.trim();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map(_text)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return const <String, String>{};
    return _normalizeMap(value.map(
      (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
    ));
  }

  Map<String, String> _normalizeMap(Map<String, String> value) {
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isNotEmpty) result[key] = entry.value.trim();
    }
    return result;
  }

  List<Map<String, dynamic>> _settings(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final result = <Map<String, dynamic>>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final map = raw.map((key, item) => MapEntry(key.toString(), item));
      final key = _text(map['key']);
      final settingValue = _text(map['value']);
      if (key.isEmpty || settingValue.isEmpty) continue;
      result.add(<String, dynamic>{
        'key': key,
        'value': settingValue,
        'relate': _stringList(map['relate']),
      });
    }
    return result;
  }
}
