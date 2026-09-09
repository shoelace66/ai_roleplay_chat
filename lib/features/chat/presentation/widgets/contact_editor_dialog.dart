import '../../data/models/continuity_state.dart';
import '../../data/models/contact_json_example.dart';
import 'story_state_editor.dart';
import 'contact_avatar.dart';
import '../../../../core/utils/avatar_image.dart';
import 'package:flutter/material.dart';

import '../../../../infrastructure/services/tts_service.dart';
import '../../data/models/contact.dart';

class ContactDraft {
  const ContactDraft({
    required this.name,
    required this.avatar,
    required this.fixedInput,
    required this.currentStates,
    required this.category,
    this.voice = '',
    this.continuity = const ContinuityState.empty(),
    this.jsonString,
    this.naturalLanguage,
  });

  final ContinuityState continuity;
  final String name;
  final String avatar;
  final String fixedInput;
  final Map<String, String> currentStates;
  final ContactCategory category;
  final String voice;
  final String? jsonString;
  final String? naturalLanguage;

  bool get isJsonMode => jsonString != null;
  bool get isNaturalLanguageMode => naturalLanguage != null;
}

class ContactEditorDialog extends StatefulWidget {
  const ContactEditorDialog({super.key});

  @override
  State<ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _avatarCtrl = TextEditingController();
  final TextEditingController _fixedInputCtrl = TextEditingController();
  final TextEditingController _fullContextCtrl = TextEditingController();
  final TextEditingController _jsonCtrl = TextEditingController();
  final TextEditingController _nlCtrl = TextEditingController();

  ContinuityState _state = const ContinuityState.empty();
  Map<String, String> get _currentStates => _state.byName;
  ContactCategory _category = ContactCategory.contact;
  String _voiceId = VoiceOption.fallback.id;
  _EditorMode _mode = _EditorMode.normal;
  String? _photoAvatar;
  bool _pickingAvatar = false;
  String get _avatar => _photoAvatar ?? _avatarCtrl.text.trim();

  Future<void> _chooseAvatar() async {
    setState(() => _pickingAvatar = true);
    try {
      final value = await AvatarImage.pick();
      if (value != null && mounted) setState(() => _photoAvatar = value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(error is FormatException ? error.message : '照片选择失败，请重试'),
        ));
      }
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _avatarCtrl.dispose();
    _fixedInputCtrl.dispose();
    _fullContextCtrl.dispose();
    _jsonCtrl.dispose();
    _nlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: SizedBox(
          width: 720,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _category == ContactCategory.story
                        ? '创建故事'
                        : _category == ContactCategory.assistant
                            ? '创建助手'
                            : '创建角色',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildContent(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: _pickingAvatar ? null : _onSave,
                      child: const Text('创建'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case _EditorMode.normal:
        return _buildNormalForm();
      case _EditorMode.json:
        return _buildJsonForm();
      case _EditorMode.naturalLanguage:
        return _buildNaturalLanguageForm();
    }
  }

  Widget _buildTypeSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('角色'),
          selected: _category == ContactCategory.contact,
          onSelected: (selected) {
            if (selected) setState(() => _category = ContactCategory.contact);
          },
        ),
        ChoiceChip(
          label: const Text('故事'),
          selected: _category == ContactCategory.story,
          onSelected: (selected) {
            if (selected) setState(() => _category = ContactCategory.story);
          },
        ),
        ChoiceChip(
          label: const Text('助手'),
          selected: _category == ContactCategory.assistant,
          onSelected: (selected) {
            if (selected) setState(() => _category = ContactCategory.assistant);
          },
        ),
      ],
    );
  }

  Widget _buildSharedFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mode in _EditorMode.values)
              ChoiceChip(
                label: Text(switch (mode) {
                  _EditorMode.normal => '表单创建',
                  _EditorMode.json => '使用 JSON 创建',
                  _EditorMode.naturalLanguage => '使用自然语言创建',
                }),
                selected: _mode == mode,
                onSelected: (_) => setState(() => _mode = mode),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTypeSelector(),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: _category == ContactCategory.story
                ? '故事名称'
                : _category == ContactCategory.assistant
                    ? '助手名称'
                    : '角色名称',
          ),
        ),
        const SizedBox(height: 12),
        if (_photoAvatar == null)
          TextField(
            controller: _avatarCtrl,
            decoration: const InputDecoration(
                labelText: '头像', hintText: '一个 emoji 或简短符号'),
          ),
        const SizedBox(height: 8),
        Row(children: [
          if (_photoAvatar != null)
            ContactAvatar(avatar: _photoAvatar!, name: _nameCtrl.text),
          Expanded(
              child: TextButton.icon(
            onPressed: _pickingAvatar ? null : _chooseAvatar,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_pickingAvatar ? '正在读取…' : '选择 JPG / PNG 照片'),
          )),
          if (_photoAvatar != null)
            IconButton(
                tooltip: '移除照片',
                onPressed: () => setState(() => _photoAvatar = null),
                icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 12),
        _buildVoiceSelector(),
      ],
    );
  }

  Widget _buildTextSection({
    required String title,
    required TextEditingController controller,
    required int minLines,
    int? maxLines,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: hintText,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  String get _mergedFixedInput {
    final fixedInput = _fixedInputCtrl.text.trim();
    final contextText = _fullContextCtrl.text.trim();
    if (contextText.isEmpty) return fixedInput;
    if (fixedInput.isEmpty) return contextText;
    return '$fixedInput\n\n$contextText';
  }

  Widget _buildVoiceSelector() {
    final selected = VoiceOption.findById(_voiceId) ?? VoiceOption.fallback;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '语音音色',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selected.id,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _voiceId = value);
                },
                items: [
                  for (final v in VoiceOption.presets)
                    DropdownMenuItem<String>(
                      value: v.id,
                      child: Row(
                        children: [
                          const Icon(Icons.record_voice_over_outlined,
                              size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              v.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            v.locale,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => _previewVoice(selected),
            tooltip: '试听音色',
            icon: const Icon(Icons.volume_up_outlined, size: 20),
          ),
        ],
      ),
    );
  }

  void _previewVoice(VoiceOption voice) {
    final tts = TtsService.instance;
    tts.stop();
    tts.speak(
      messageId: '__preview__',
      text: '你好，我是语音助手。这是$voice',
      voice: voice,
    );
  }

  Widget _buildNormalForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSharedFields(),
          const SizedBox(height: 16),
          _buildTextSection(
            title: '固定输入内容',
            controller: _fixedInputCtrl,
            minLines: 3,
            maxLines: 8,
            hintText: '每轮对话固定输入的提示词',
          ),
          const SizedBox(height: 16),
          _buildTextSection(
            title: '全量输入上下文（正文）',
            controller: _fullContextCtrl,
            minLines: 8,
            maxLines: 16,
            hintText: '可粘贴完整上下文正文，作为固定输入内容的正文补充',
          ),
          const SizedBox(height: 16),
          StoryStateEditor(
              value: _state,
              onChanged: (value) => setState(() => _state = value)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildJsonForm() {
    if (_jsonCtrl.text.isEmpty) {
      _jsonCtrl.text = contactJsonExample;
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSharedFields(),
          const SizedBox(height: 12),
          TextField(
            controller: _jsonCtrl,
            minLines: 14,
            maxLines: 20,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'JSON 格式',
              hintText: '粘贴角色或故事 JSON，下一步会检查并显示具体问题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '支持中英文字段名、常见拼写差异、代码块、注释和尾随逗号；创建前会显示兼容调整及具体错误，原文可继续修改。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            '状态定义使用 id / label / type / description / defaultValue，可选 enum 和 updateRule。'
            'values 按 id 保存当前值，省略某项时使用默认值。type 支持 string、int、enum；'
            'enum 限制非空值，空字符串表示明确清空。旧 name / initialValue 仍可导入。',
            style: TextStyle(fontSize: 12),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _mode = _EditorMode.normal),
              child: const Text('返回普通模式'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNaturalLanguageForm() {
    if (_nlCtrl.text.isEmpty) {
      _nlCtrl.text = '创建一个角色，固定输入内容是：你是……；需要记录的状态有：好感度、当前位置，风格上要偏向成熟稳重。';
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSharedFields(),
          const SizedBox(height: 12),
          TextField(
            controller: _nlCtrl,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: const InputDecoration(
              labelText: '自然语言描述',
              hintText: '例如：一个擅长观察、善于分析的侦探角色，沉默寡言但会主动引导用户对话。',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _mode = _EditorMode.normal),
              child: const Text('返回普通模式'),
            ),
          ),
        ],
      ),
    );
  }

  void _onSave() {
    switch (_mode) {
      case _EditorMode.normal:
        _saveNormalMode();
        break;
      case _EditorMode.json:
        _saveJsonMode();
        break;
      case _EditorMode.naturalLanguage:
        _saveNaturalLanguageMode();
        break;
    }
  }

  ContactDraft _draft({String? jsonString, String? naturalLanguage}) {
    // 助手类型如果没有 fixedInput，设置默认值
    final rawFixedInput = naturalLanguage?.trim().isNotEmpty == true
        ? (_mergedFixedInput.isNotEmpty
            ? _mergedFixedInput
            : naturalLanguage!.trim())
        : _mergedFixedInput;
    String fixedInput = rawFixedInput;
    if (fixedInput.isEmpty && _category == ContactCategory.assistant) {
      fixedInput = '你是一个AI助手，专注于帮助用户完成任务。';
    }

    return ContactDraft(
      name: _nameCtrl.text.trim(),
      avatar: _avatar,
      fixedInput: fixedInput,
      currentStates: Map<String, String>.from(_currentStates),
      continuity: _state,
      category: _category,
      voice: _voiceId,
      jsonString: jsonString,
      naturalLanguage: naturalLanguage,
    );
  }

  void _saveNormalMode() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(_draft());
  }

  void _saveJsonMode() {
    final jsonStr = _jsonCtrl.text.trim();
    if (jsonStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON 不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(_draft(jsonString: jsonStr));
  }

  void _saveNaturalLanguageMode() {
    final nlText = _nlCtrl.text.trim();
    if (nlText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('描述不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(
      ContactDraft(
        name: _nameCtrl.text.trim(),
        avatar: _avatar,
        fixedInput: _mergedFixedInput.isEmpty ? nlText : _mergedFixedInput,
        currentStates: Map<String, String>.from(_currentStates),
        continuity: _state,
        category: _category,
        voice: _voiceId,
        naturalLanguage: nlText,
      ),
    );
  }
}

enum _EditorMode {
  normal,
  json,
  naturalLanguage,
}
