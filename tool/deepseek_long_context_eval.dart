import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_chat_demo/core/data/models/app_settings.dart';
import 'package:flutter_chat_demo/core/utils/structured_input_prompt_composer.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/roleplay_turn.dart';

const _model = 'deepseek-chat';
const _baseUrl = 'https://api.deepseek.com/chat/completions';
const _usdToCny = 7.2;
// Conservative peak rates from DeepSeek's current pricing page for the
// deepseek-chat compatibility mapping to V4 Flash. The script stops before
// this upper-bound estimate reaches the user's 10 CNY budget.
const _cacheHitUsdPerMillion = 0.014;
const _cacheMissUsdPerMillion = 0.44;
const _outputUsdPerMillion = 1.32;
const _hardBudgetCny = 8.0;

class _TurnSpec {
  const _TurnSpec(this.input,
      {this.expectedState, this.expectedReplyTerms = const []});
  final String input;
  final Map<String, String>? expectedState;
  final List<String> expectedReplyTerms;
}

class _Usage {
  _Usage(
      {required this.prompt,
      required this.output,
      required this.hit,
      required this.miss});
  final int prompt;
  final int output;
  final int hit;
  final int miss;
  int get total => prompt + output;
  double get estimatedUsd =>
      hit / 1000000 * _cacheHitUsdPerMillion +
      miss / 1000000 * _cacheMissUsdPerMillion +
      output / 1000000 * _outputUsdPerMillion;
}

class _TurnResult {
  _TurnResult(
      {required this.number,
      required this.usage,
      required this.latencyMs,
      required this.expectedState,
      required this.expectedReplyTerms})
      : valid = false,
        revisionMatch = false,
        stateChangesValid = false,
        expectedStateMatched = false,
        probeMatched = false;
  final int number;
  final _Usage usage;
  final int latencyMs;
  final Map<String, String>? expectedState;
  final List<String> expectedReplyTerms;
  bool valid;
  bool revisionMatch;
  bool stateChangesValid;
  bool expectedStateMatched;
  bool probeMatched;
  String error = '';
  String reply = '';
  String raw = '';
}

class _ScenarioResult {
  _ScenarioResult(this.name, this.turns, this.initial, this.finalContact);
  final String name;
  final List<_TurnResult> turns;
  final Contact initial;
  final Contact finalContact;
  int get valid => turns.where((t) => t.valid).length;
  int get revisionMatches => turns.where((t) => t.revisionMatch).length;
  int get stateChangesValid => turns.where((t) => t.stateChangesValid).length;
  int get expectedStateMatched =>
      turns.where((t) => t.expectedStateMatched).length;
  int get probes => turns.where((t) => t.expectedReplyTerms.isNotEmpty).length;
  int get probeHits => turns.where((t) => t.probeMatched).length;
  int get promptTokens => turns.fold(0, (sum, t) => sum + t.usage.prompt);
  int get outputTokens => turns.fold(0, (sum, t) => sum + t.usage.output);
  int get cacheHits => turns.fold(0, (sum, t) => sum + t.usage.hit);
  int get cacheMisses => turns.fold(0, (sum, t) => sum + t.usage.miss);
  double get usd => turns.fold(0, (sum, t) => sum + t.usage.estimatedUsd);
}

Future<void> runEvaluation() async {
  final key = Platform.environment['DEEPSEEK_API_KEY']?.trim() ?? '';
  if (key.isEmpty) {
    stderr.writeln(
        'Missing DEEPSEEK_API_KEY. Pass it through the environment; it is never written to the report.');
    return;
  }

  final client = http.Client();
  try {
    final scenarios = <_ScenarioResult>[];
    final initialA = _makeContact('story-a', '临海车站的雨夜', <StateDefinition>[
      const StateDefinition(
          id: 'location',
          name: '当前地点',
          description: '持续记录角色所在的具体地点。',
          initialValue: '临海旧车站月台',
          updateRule: '只有正文明确移动后才更新。'),
      const StateDefinition(
          id: 'weather',
          name: '天气',
          description: '记录正在影响叙事的天气。',
          initialValue: '细雨',
          updateRule: '只在正文明确变化时更新。'),
      const StateDefinition(
          id: 'outfit',
          name: '衣着',
          description: '记录角色当前穿着及明显变化。',
          initialValue: '深蓝防水外套，袖口沾泥',
          updateRule: '保留未改变的穿着细节。'),
      const StateDefinition(
          id: 'key',
          name: '铜钥匙位置',
          description: '记录铜钥匙当前确切位置。',
          initialValue: '右侧口袋',
          updateRule: '物品位置改变时必须更新，不能凭空消失。'),
    ]);
    scenarios.add(await _runScenario(client, key, initialA, _scenarioA()));

    final initialB = _makeContact('story-b', '山城档案馆的冬日', <StateDefinition>[
      const StateDefinition(
          id: 'location',
          name: '当前地点',
          description: '记录故事地点。',
          initialValue: '山城档案馆地下阅览室',
          updateRule: '移动后才更新。'),
      const StateDefinition(
          id: 'temperature',
          name: '室内温度',
          description: '记录室内体感温度。',
          initialValue: '寒冷',
          updateRule: '只根据明确描写更新。'),
      const StateDefinition(
          id: 'scarf',
          name: '围巾',
          description: '记录围巾的颜色和位置。',
          initialValue: '墨绿色围巾围在脖子上',
          updateRule: '除非明确取下，否则保持。'),
      const StateDefinition(
          id: 'archiveKey',
          name: '档案钥匙位置',
          description: '记录钥匙位置。',
          initialValue: '夹在借阅证后面',
          updateRule: '位置变化必须更新。'),
    ]);
    scenarios.add(await _runScenario(client, key, initialB, _scenarioB()));

    final report = _renderReport(scenarios);
    final reportPath =
        'reports/deepseek_long_context_eval_${DateTime.now().toIso8601String().substring(0, 10)}.md';
    await Directory('reports').create(recursive: true);
    await File(reportPath).writeAsString(report);
    stdout.writeln('REPORT=$reportPath');
    stdout.writeln(report);
  } finally {
    client.close();
  }
}

Future<void> main() => runEvaluation();

Contact _makeContact(
    String id, String name, List<StateDefinition> definitions) {
  return Contact(
    id: id,
    name: name,
    avatar: '',
    category: ContactCategory.story,
    fixedInput: '这是一个连续叙事测试。人物说话克制，尊重已经发生的事实，不凭空重置状态。',
    narrativeRules: const ['承接上一轮结尾', '用简洁中文续写', '保持既有物品和衣着连续'],
    continuity: ContinuityState(
      revision: 0,
      definitions: definitions,
      values: {for (final d in definitions) d.id: d.initialValue},
    ),
    createdAt: DateTime(2026, 9, 7),
  );
}

List<_TurnSpec> _scenarioA() => const [
      _TurnSpec('先不要改变地点。她检查月台尽头的旧时刻表，注意雨声和袖口的泥。'),
      _TurnSpec('她听见远处有列车经过，但仍留在月台。让她观察环境。'),
      _TurnSpec('她把铜钥匙从右侧口袋拿出来，放在月台长椅上，然后伸手压住它。',
          expectedState: {'key': '月台长椅'}),
      _TurnSpec('继续描写她等待，不要改变铜钥匙位置。'),
      _TurnSpec('请承接现在的结尾，并自然提到当前地点、天气和铜钥匙的位置。',
          expectedReplyTerms: ['临海', '细雨', '月台长椅']),
      _TurnSpec('雨势突然变大，月台积水漫过鞋底，但她仍不离开。', expectedState: {'weather': '暴雨'}),
      _TurnSpec('她用外套下摆遮住时刻表，保留铜钥匙在长椅上的事实。'),
      _TurnSpec('远处的检票灯亮了一次又熄灭，继续写她的反应。'),
      _TurnSpec('她把湿透的外套脱下搭在长椅背上，露出里面的灰色针织衫。',
          expectedState: {'outfit': '灰色针织衫'}),
      _TurnSpec('不要把外套重新穿回去。她查看月台出口。'),
      _TurnSpec('请回顾并自然提到：她现在在哪、天气如何、钥匙在哪里、外套是否穿着。',
          expectedReplyTerms: ['月台', '暴雨', '长椅', '灰色']),
      _TurnSpec('她走进旧车站候车厅，铜钥匙仍留在月台长椅上。', expectedState: {'location': '候车厅'}),
      _TurnSpec('候车厅没有开灯，她摸索墙上的电闸。'),
      _TurnSpec('她找到一张被雨水打湿的车票，先不要改变钥匙位置。'),
      _TurnSpec('在继续之前，准确说出铜钥匙和深蓝外套分别在哪里。', expectedReplyTerms: ['长椅', '外套']),
      _TurnSpec('她返回月台取回铜钥匙，再把它握在右手里。', expectedState: {'key': '右手'}),
      _TurnSpec('她把外套重新穿上，袖口仍沾泥。', expectedState: {'outfit': '深蓝防水外套'}),
      _TurnSpec('列车停靠又离开，她没有上车。'),
      _TurnSpec('她在车站公告栏后发现一张手写地图。'),
      _TurnSpec('请自然提及她没有上车、钥匙现在在右手，以及她仍在旧车站。',
          expectedReplyTerms: ['没有上车', '右手', '车站']),
      _TurnSpec('她沿着地图指向的通道走到车站北侧储物间。', expectedState: {'location': '北侧储物间'}),
      _TurnSpec('储物间门缝里透出暖光，但她先检查手里的钥匙。'),
      _TurnSpec('她把钥匙插进储物间的锁孔，但暂时不转动。'),
      _TurnSpec('长对话回顾：用正文确认当前地点、钥匙状态、衣着和天气。',
          expectedReplyTerms: ['储物间', '钥匙', '深蓝', '暴雨']),
      _TurnSpec('她转动钥匙打开储物间，门内没有人。'),
      _TurnSpec('她把湿车票放在储物间门口的木箱上。'),
      _TurnSpec('她听见月台方向传来第二声汽笛，保持刚刚打开门的事实。'),
      _TurnSpec('最后一次长程回顾：不要把她送回月台，也不要把钥匙放回口袋。',
          expectedReplyTerms: ['储物间', '右手', '打开']),
    ];

List<_TurnSpec> _scenarioB() => const [
      _TurnSpec('她翻阅一册没有目录的地方志，保持在地下阅览室。'),
      _TurnSpec('暖气没有工作，她用墨绿色围巾挡住脖子。'),
      _TurnSpec('她把档案钥匙从借阅证后面取出，放在桌面右上角。',
          expectedState: {'archiveKey': '桌面右上角'}),
      _TurnSpec('请继续查找，不要把围巾取下。'),
      _TurnSpec('回顾当前地点、温度、围巾和档案钥匙位置。',
          expectedReplyTerms: ['阅览室', '寒冷', '墨绿色', '桌面']),
      _TurnSpec('她打开一扇通风窗，室内更冷了。', expectedState: {'temperature': '更冷'}),
      _TurnSpec('她用铅笔标出地方志中的旧桥位置。'),
      _TurnSpec('她听见楼上传来脚步声，但没有离开座位。'),
      _TurnSpec('她把围巾解下来放在椅背上，露出白色领口。', expectedState: {'scarf': '椅背上'}),
      _TurnSpec('不要把围巾写回脖子上。她继续读档案。'),
      _TurnSpec('请准确回顾钥匙在桌面右上角，围巾在椅背上，且她仍在地下阅览室。',
          expectedReplyTerms: ['桌面', '椅背', '阅览室']),
      _TurnSpec('她走到地下阅览室的西侧书架，仍没有离开档案馆。', expectedState: {'location': '西侧书架'}),
      _TurnSpec('她从书架缝隙抽出一张旧照片。'),
      _TurnSpec('照片背面写着“冬至前归还”，她把照片夹进地方志。'),
      _TurnSpec('长程回顾：保持她在西侧书架、室内更冷、钥匙在桌面、围巾在椅背。',
          expectedReplyTerms: ['西侧书架', '更冷', '桌面', '椅背']),
      _TurnSpec('她回到桌边，拿起档案钥匙放进左手掌心。',
          expectedState: {'location': '桌边', 'archiveKey': '左手掌心'}),
      _TurnSpec('她没有戴回围巾，开始抄写照片背面的字。'),
      _TurnSpec('阅览室灯光闪烁，她用右手护住地方志。'),
      _TurnSpec('楼上传来管理员的咳嗽声，她决定继续安静工作。'),
      _TurnSpec('请回顾：钥匙在左手、围巾在哪里、室内温度和当前地点。',
          expectedReplyTerms: ['左手', '椅背', '更冷', '桌边']),
      _TurnSpec('她把钥匙放回桌面右上角，然后回到西侧书架。',
          expectedState: {'location': '西侧书架', 'archiveKey': '桌面右上角'}),
      _TurnSpec('她把照片从地方志中取出，夹在外套内袋。'),
      _TurnSpec('她听见通风窗被风吹响，围巾仍在椅背上。'),
      _TurnSpec('最终回顾：不要把档案馆写成车站，准确提到地点、温度、围巾和钥匙。',
          expectedReplyTerms: ['档案馆', '更冷', '椅背', '右上角']),
    ];

Future<_ScenarioResult> _runScenario(http.Client client, String key,
    Contact initial, List<_TurnSpec> specs) async {
  var contact = initial;
  final results = <_TurnResult>[];
  final recent = <Map<String, String>>[];
  final composer = StructuredInputPromptComposer(
      settings: const AppSettings(
          maxPromptListItems: 8,
          maxShortTermEvents: 8,
          maxLongTermEvents: 4,
          maxUltraTermEvents: 2));
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final sections = composer.composeSystemPromptSectionsWithContactObject(
      basePrompt: '这是一次长对话一致性评测。请严格遵守用户定义状态记录项。',
      contact: contact,
    );
    final user = <String>[
      '【本轮上下文】',
      sections.dynamicContext,
      '',
      '【用户输入】',
      spec.input,
    ].join('\n');
    final started = DateTime.now();
    final response = await _request(client, key, sections.cacheablePrefix, user,
        history: recent.takeLast(4).toList(growable: false));
    final result = _TurnResult(
        number: i + 1,
        usage: response.usage,
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        expectedState: spec.expectedState,
        expectedReplyTerms: spec.expectedReplyTerms);
    result.raw = response.content;
    if (response.costUpperBoundCny +
            results.fold<double>(
                0, (sum, r) => sum + r.usage.estimatedUsd * _usdToCny) >
        _hardBudgetCny) {
      throw StateError(
          'budget guard stopped before exceeding $_hardBudgetCny CNY');
    }
    try {
      final turn = RoleplayTurn.parse(
          raw: response.content,
          contact: contact,
          userInput: spec.input,
          initialContext:
              '${contact.fixedInput}\n${contact.continuity.byName.values.join('\n')}',
          allowSummary: false);
      result.valid = true;
      final transition = turn.patch['stateTransition'];
      result.revisionMatch = transition == null ||
          (transition is Map &&
              transition['baseRevision'] == contact.continuity.revision);
      result.stateChangesValid =
          result.revisionMatch && (transition == null || transition is Map);
      if (transition is Map && transition['changes'] is List) {
        for (final change in transition['changes']) {
          if (change is! Map ||
              change['key'] is! String ||
              change['from'] is! String ||
              change['to'] is! String ||
              !contact.continuity.values.containsKey(change['key'])) {
            result.stateChangesValid = false;
          }
        }
      }
      if (spec.expectedState != null) {
        result.expectedStateMatched =
            spec.expectedState!.entries.every((entry) {
          final changes = transition is Map && transition['changes'] is List
              ? transition['changes'] as List
              : const [];
          final matching = changes
              .whereType<Map>()
              .where((c) => c['key'] == entry.key)
              .toList();
          final match = matching.isEmpty ? null : matching.first;
          return match != null && (match['to'] as String).contains(entry.value);
        });
      }
      result.reply = turn.reply;
      result.probeMatched = spec.expectedReplyTerms.isNotEmpty &&
          spec.expectedReplyTerms.every((term) =>
              turn.reply.contains(term) ||
              (turn.memory.turnEvent?.description.contains(term) ?? false));
      final event = turn.memory.turnEvent;
      final nodes = event == null
          ? contact.eventGraph.shortTermQueue
          : <EventNode>[
              ...contact.eventGraph.shortTermQueue,
              EventNode(
                  id: '${contact.id}-turn-${i + 1}',
                  tier: EventTier.shortTerm,
                  event: event,
                  createdAtMs: DateTime.now().millisecondsSinceEpoch),
            ];
      contact = contact.copyWith(
          continuity: turn.memory.continuity,
          eventGraph: contact.eventGraph.copyWith(shortTermQueue: nodes),
          worldKnowledge: WorldKnowledgeBucket(turn.memory.worldKnowledge),
          selfKnowledge: SelfKnowledgeBucket(turn.memory.selfKnowledge),
          userKnowledge: UserKnowledgeBucket(turn.memory.userKnowledge));
    } catch (error) {
      result.error = error.toString();
    }
    results.add(result);
    recent.add({'role': 'user', 'content': spec.input});
    recent.add({
      'role': 'assistant',
      'content': result.reply.isEmpty ? '[结构化响应无效]' : result.reply
    });
  }
  return _ScenarioResult(initial.name, results, initial, contact);
}

Future<_Response> _request(
    http.Client client, String key, String system, String user,
    {List<Map<String, String>> history = const <Map<String, String>>[]}) async {
  final response = await client
      .post(Uri.parse(_baseUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'model': _model,
            'messages': [
              {'role': 'system', 'content': system},
              ...history,
              {'role': 'user', 'content': user}
            ],
            'temperature': 0.3,
            'max_tokens': 500,
            'stream': false
          }))
      .timeout(const Duration(seconds: 90));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
        'DeepSeek HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 500))}');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final usage = body['usage'] is Map ? body['usage'] as Map : const {};
  final prompt = _intValue(usage['prompt_tokens']);
  final output = _intValue(usage['completion_tokens']);
  final hit = _intValue(usage['prompt_cache_hit_tokens']);
  final miss = _intValue(usage['prompt_cache_miss_tokens'],
      fallback: (prompt - hit).clamp(0, prompt));
  final content =
      (((body['choices'] as List).first as Map)['message'] as Map)['content']
              ?.toString() ??
          '';
  return _Response(
      content: content,
      usage: _Usage(prompt: prompt, output: output, hit: hit, miss: miss),
      costUpperBoundCny: (hit * _cacheHitUsdPerMillion +
              miss * _cacheMissUsdPerMillion +
              output * _outputUsdPerMillion) /
          1000000 *
          _usdToCny);
}

int _intValue(dynamic value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

class _Response {
  _Response(
      {required this.content,
      required this.usage,
      required this.costUpperBoundCny});
  final String content;
  final _Usage usage;
  final double costUpperBoundCny;
}

extension<T> on List<T> {
  List<T> takeLast(int count) =>
      skip(length > count ? length - count : 0).toList();
}

String _renderReport(List<_ScenarioResult> scenarios) {
  final totalTurns = scenarios.fold(0, (sum, s) => sum + s.turns.length);
  final valid = scenarios.fold(0, (sum, s) => sum + s.valid);
  final revisions = scenarios.fold(0, (sum, s) => sum + s.revisionMatches);
  final stateChanges = scenarios.fold(0, (sum, s) => sum + s.stateChangesValid);
  final expected = scenarios.fold(0, (sum, s) => sum + s.expectedStateMatched);
  final probes = scenarios.fold(0, (sum, s) => sum + s.probes);
  final probeHits = scenarios.fold(0, (sum, s) => sum + s.probeHits);
  final prompt = scenarios.fold(0, (sum, s) => sum + s.promptTokens);
  final output = scenarios.fold(0, (sum, s) => sum + s.outputTokens);
  final hit = scenarios.fold(0, (sum, s) => sum + s.cacheHits);
  final miss = scenarios.fold(0, (sum, s) => sum + s.cacheMisses);
  final usd = scenarios.fold(0.0, (sum, s) => sum + s.usd);
  final lines = <String>[
    '# DeepSeek 长对话一致性与缓存命中评测',
    '',
    '- 评测日期：${DateTime.now().toIso8601String()}',
    '- 模型：`$_model`，请求地址：`https://api.deepseek.com/chat/completions`',
    '- 评测轮数：$totalTurns（${scenarios.length} 套完全不同的故事状态定义）',
    '- API Key：已使用，但报告不记录密钥。',
    '- 预算保护：按当前官方峰值价格的保守上界估算，超过 ${_hardBudgetCny.toStringAsFixed(2)} 元会自动停止；本次实际请求总额按 token usage 估算。',
    '- 价格依据：[DeepSeek Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing)。',
    '',
    '## 指标',
    '',
    '| 指标 | 结果 |',
    '|---|---:|',
    '| 结构化响应通过率 | ${_pct(valid, totalTurns)} |',
    '| 状态版本匹配率 | ${_pct(revisions, totalTurns)} |',
    '| 状态字段本地校验通过率 | ${_pct(stateChanges, totalTurns)} |',
    '| 预设状态变化命中率 | ${_pct(expected, scenarios.fold(0, (sum, s) => sum + s.turns.where((t) => t.expectedState != null).length))} |',
    '| 长程事实探针命中率 | ${_pct(probeHits, probes)}（$probeHits/$probes） |',
    '| API 输入 token | $prompt |',
    '| API 输出 token | $output |',
    '| API 缓存命中 token | $hit |',
    '| API 缓存未命中 token | $miss |',
    '| API 缓存命中率 | ${_pct(hit, hit + miss)} |',
    '| 按保守峰值费率估算 | ¥${(usd * _usdToCny).toStringAsFixed(4)} |',
    '',
    '## 分故事结果',
    '',
  ];
  for (final scenario in scenarios) {
    lines.add('### ${scenario.name}');
    lines.add('');
    lines.add(
        '| 轮次 | 有效 | 版本 | 状态校验 | 预设变化 | 探针 | 输入 token | 缓存命中 | 输出 token | 延迟 |');
    lines.add('|---:|:---:|:---:|:---:|:---:|:---:|---:|---:|---:|---:|');
    for (final turn in scenario.turns) {
      lines.add(
          '| ${turn.number} | ${turn.valid ? '✓' : '✗'} | ${turn.revisionMatch ? '✓' : '✗'} | ${turn.stateChangesValid ? '✓' : '✗'} | ${turn.expectedState == null ? '-' : turn.expectedStateMatched ? '✓' : '✗'} | ${turn.expectedReplyTerms.isEmpty ? '-' : turn.probeMatched ? '✓' : '✗'} | ${turn.usage.prompt} | ${turn.usage.hit} | ${turn.usage.output} | ${turn.latencyMs}ms |');
      if (turn.error.isNotEmpty) {
        lines.add(
            '  - 轮次 ${turn.number} 本地校验：`${turn.error.replaceAll('`', "'")}`');
      }
    }
    lines.add('');
    lines.add('最终状态：');
    for (final definition in scenario.finalContact.continuity.definitions) {
      lines.add(
          '- `${definition.name}`：${scenario.finalContact.continuity.values[definition.id] ?? definition.initialValue}');
    }
    lines.add('');
  }
  lines.addAll([
    '## 判读',
    '',
    '“结构化响应通过率”和“状态字段本地校验通过率”衡量模型是否遵守项目协议；“长程事实探针命中率”只统计明确要求回顾的轮次。API 缓存命中率直接来自 DeepSeek 返回的 `prompt_cache_hit_tokens / (prompt_cache_hit_tokens + prompt_cache_miss_tokens)`，不由本地字符串长度推算。',
    '',
    '本次评测只代表当前两套故事定义、当前 Prompt 和当前模型配置；它不能证明所有自然语言状态规则都能被模型正确理解。真实费用以 DeepSeek 控制台扣费为准，报告中的金额是按保守峰值费率和返回 token usage 的估算。',
    '',
    '## 复现',
    '',
    '```powershell',
    '\$env:DEEPSEEK_API_KEY = "<your-key>"',
    'flutter test --no-pub test/integration/deepseek_live_eval_test.dart --reporter expanded',
    '```',
  ]);
  return '${lines.join('\n')}\n';
}

String _pct(int numerator, int denominator) => denominator == 0
    ? 'n/a'
    : '${(numerator / denominator * 100).toStringAsFixed(1)}%';
