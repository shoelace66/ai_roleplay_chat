import 'package:flutter/material.dart';

import '../../data/models/contact.dart';

class ContactDraft {
  const ContactDraft({
    required this.name,
    required this.id,
    required this.avatar,
    required this.personality,
    this.appearance,
    this.settings,
    required this.backgroundStory,
    required this.category,
    this.jsonString,
    this.naturalLanguage,
  });

  final String name;
  final String id;
  final String avatar;
  final List<String> personality;
  final List<String>? appearance;
  final List<Map<String, dynamic>>? settings;
  final List<String> backgroundStory;
  final ContactCategory category;
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
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _avatarCtrl = TextEditingController();
  final TextEditingController _personalityCtrl = TextEditingController();
  final TextEditingController _appearanceCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();

  final List<String> _personality = <String>[];
  final List<String> _appearance = <String>[];
  final List<String> _backgroundStory = <String>[];

  ContactCategory _category = ContactCategory.contact;
  _EditorMode _mode = _EditorMode.normal;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _avatarCtrl.dispose();
    _personalityCtrl.dispose();
    _appearanceCtrl.dispose();
    _backgroundCtrl.dispose();
    super.dispose();
  }

  void _appendItem(List<String> items, TextEditingController controller) {
    final input = controller.text.trim();
    if (input.isEmpty) return;
    setState(() {
      items.add(input);
      controller.clear();
    });
  }

  Future<void> _editItem(List<String> items, int index) async {
    final editCtrl = TextEditingController(text: items[index]);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改条目'),
          content: TextField(
            controller: editCtrl,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(editCtrl.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    editCtrl.dispose();
    if (value == null || value.trim().isEmpty) return;
    setState(() => items[index] = value.trim());
  }

  Widget _buildArrayEditor({
    required String title,
    required String hint,
    required List<String> items,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(hintText: hint),
                onSubmitted: (_) => _appendItem(items, controller),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _appendItem(items, controller),
              child: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          const Text('暂无条目', style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < items.length; i++)
                InputChip(
                  label: Text(items[i]),
                  onPressed: () => _editItem(items, i),
                  onDeleted: () => setState(() => items.removeAt(i)),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _category == ContactCategory.story ? '创建故事' : '创建角色',
      ),
      content: SizedBox(
        width: 480,
        child: _buildContent(),
      ),
      actions: _buildActions(),
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

  Widget _buildNormalForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RadioListTile<ContactCategory>(
                  title: const Text('角色'),
                  value: ContactCategory.contact,
                  groupValue: _category,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
                ),
              ),
              Expanded(
                child: RadioListTile<ContactCategory>(
                  title: const Text('故事'),
                  value: ContactCategory.story,
                  groupValue: _category,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
                ),
              ),
            ],
          ),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: _category == ContactCategory.story ? '故事名称' : '角色名称',
              hintText:
                  _category == ContactCategory.story ? '请输入故事名称' : '请输入角色名称',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              labelText: 'ID',
              hintText: '唯一标识符，如 character-001',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _avatarCtrl,
            decoration: const InputDecoration(
              labelText: '头像',
              hintText: '一个 emoji 或简短符号',
            ),
          ),
          const SizedBox(height: 16),
          if (_category == ContactCategory.contact) ...[
            _buildArrayEditor(
              title: '外貌特征',
              hint: '输入外貌特征后点击添加',
              items: _appearance,
              controller: _appearanceCtrl,
            ),
            const SizedBox(height: 16),
          ],
          _buildArrayEditor(
            title: _category == ContactCategory.story ? '风格' : '性格特点',
            hint: _category == ContactCategory.story
                ? '输入风格标签后点击添加，如：奇幻、冒险'
                : '输入性格特点后点击添加，如：理性、冷静',
            items: _personality,
            controller: _personalityCtrl,
          ),
          const SizedBox(height: 16),
          _buildArrayEditor(
            title: _category == ContactCategory.story ? '背景概述' : '背景故事',
            hint: '输入背景内容后点击添加',
            items: _backgroundStory,
            controller: _backgroundCtrl,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _mode = _EditorMode.json),
                child: const Text('使用 JSON 创建'),
              ),
              const SizedBox(width: 20),
              TextButton(
                onPressed: () =>
                    setState(() => _mode = _EditorMode.naturalLanguage),
                child: const Text('使用自然语言创建'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJsonForm() {
    final TextEditingController jsonCtrl = TextEditingController();
    final example = _category == ContactCategory.story
        ? '''{
  "id": "story-001",
  "name": "魔法世界",
  "avatar": "🏰",
  "personality": ["奇幻", "冒险"],
  "backgroundStory": ["一个充满魔法的世界"]
}'''
        : '''{
  "id": "character-001",
  "name": "阿星",
  "avatar": "⭐",
  "personality": ["理性", "冷静"],
  "appearance": ["黑色外套", "短发"],
  "backgroundStory": ["资深侦探"]
}''';
    jsonCtrl.text = example;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('角色'),
                value: ContactCategory.contact,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('故事'),
                value: ContactCategory.story,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
          ],
        ),
        TextField(
          controller: jsonCtrl,
          minLines: 10,
          maxLines: 15,
          decoration: const InputDecoration(
            labelText: 'JSON 格式',
            hintText: '请输入标准 JSON 格式',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _mode = _EditorMode.normal),
            child: const Text('返回普通模式'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () =>
                setState(() => _mode = _EditorMode.naturalLanguage),
            child: const Text('使用自然语言创建'),
          ),
        ),
      ],
    );
  }

  Widget _buildNaturalLanguageForm() {
    final TextEditingController nlCtrl = TextEditingController(
      text: _category == ContactCategory.story
          ? '创建一个魔法世界的故事，包含魔法师、魔法石等元素'
          : '创建一个名叫阿星的侦探，性格理性冷静，穿着黑色外套',
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('角色'),
                value: ContactCategory.contact,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
            Expanded(
              child: RadioListTile<ContactCategory>(
                title: const Text('故事'),
                value: ContactCategory.story,
                groupValue: _category,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ),
          ],
        ),
        TextField(
          controller: nlCtrl,
          minLines: 6,
          maxLines: 10,
          decoration: InputDecoration(
            labelText: '自然语言描述',
            hintText: _category == ContactCategory.story
                ? '描述你的故事世界观和设定'
                : '描述你的角色特征和背景',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _mode = _EditorMode.normal),
            child: const Text('返回普通模式'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _mode = _EditorMode.json),
            child: const Text('使用 JSON 创建'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _onSave,
        child: const Text('创建'),
      ),
    ];
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

  void _saveNormalMode() {
    final name = _nameCtrl.text.trim();
    final id = _idCtrl.text.trim();
    final avatar = _avatarCtrl.text.trim();

    if (name.isEmpty || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称和 ID 不能为空')),
      );
      return;
    }

    Navigator.of(context).pop(
      ContactDraft(
        name: name,
        id: id,
        avatar: avatar,
        personality: List<String>.from(_personality),
        appearance: _category == ContactCategory.contact
            ? List<String>.from(_appearance)
            : null,
        backgroundStory: List<String>.from(_backgroundStory),
        category: _category,
      ),
    );
  }

  void _saveJsonMode() {
    Navigator.of(context).pop(
      ContactDraft(
        name: '',
        id: '',
        avatar: '',
        personality: const [],
        backgroundStory: const [],
        category: _category,
        jsonString: '{}',
      ),
    );
  }

  void _saveNaturalLanguageMode() {
    Navigator.of(context).pop(
      ContactDraft(
        name: '',
        id: '',
        avatar: '',
        personality: const [],
        backgroundStory: const [],
        category: _category,
        naturalLanguage: '创建一个角色',
      ),
    );
  }
}

enum _EditorMode {
  normal,
  json,
  naturalLanguage,
}
