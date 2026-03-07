import 'dart:async';

import 'package:flutter/material.dart';

import 'features/chat/data/models/contact.dart';
import 'features/chat/data/models/message.dart';
import 'features/chat/domain/providers/chat_provider.dart';
import 'features/chat/domain/services/heartbeat_manager.dart';

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatProvider _provider = ChatProvider();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_scrollToBottom);
    unawaited(_provider.initialize());
  }

  @override
  void dispose() {
    _provider.removeListener(_scrollToBottom);
    _provider.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    scheduleMicrotask(() {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final input = _inputController.text;
    if (input.trim().isEmpty) return;
    _inputController.clear();
    await _provider.sendMessage(input);
  }

  Future<void> _openApiSettingDialog() async {
    final keyCtrl = TextEditingController(text: _provider.currentApiKey);
    final promptCtrl =
        TextEditingController(text: _provider.currentSystemPrompt);

    final result = await showDialog<_ApiConfigDraft>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('API 配置'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: '请输入 API Key',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: promptCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '系统提示词',
                    hintText: '可选：定义全局系统提示词',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _ApiConfigDraft(
                    apiKey: keyCtrl.text,
                    systemPrompt: promptCtrl.text,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    await _provider.saveApiKey(result.apiKey);
    await _provider.saveSystemPrompt(result.systemPrompt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API 配置已保存')),
    );
  }

  Future<void> _openCreateContactDialog() async {
    final result = await showDialog<_ContactDraft>(
      context: context,
      builder: (context) => const _ContactEditorDialog(),
    );
    if (result == null) return;

    final categoryLabel =
        result.category == ContactCategory.story ? '故事' : '角色';

    // 判断是否是自然语言模式
    if (result.isNaturalLanguageMode) {
      // 显示加载提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('正在使用 AI 生成$categoryLabel...')),
        );
      }

      // 调用 LLM 转换
      final jsonStr = await _provider.convertNaturalLanguageToJson(
        result.naturalLanguage!,
      );

      if (!mounted) return;

      if (jsonStr == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 转换失败，请检查描述或稍后重试')),
        );
        return;
      }

      // 使用转换后的 JSON 创建角色
      final ok = await _provider.addContactFromJson(
        jsonStr,
        category: result.category,
      );
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败：生成的 JSON 无效或 ID 已存在')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 生成$categoryLabel成功')),
      );
      return;
    }

    // 判断是否是 JSON 模式
    if (result.isJsonMode) {
      final ok = await _provider.addContactFromJson(
        result.jsonString!,
        category: result.category,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败：JSON 格式错误或 ID 已存在')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$categoryLabel创建成功')),
      );
    } else {
      final ok = await _provider.addContact(
        name: result.name,
        contactId: result.id,
        avatar: result.avatar,
        personality: result.personality,
        appearance: result.appearance ?? [],
        settings: result.settings ?? [],
        backgroundStory: result.backgroundStory,
        category: result.category,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败：名称/ID 不能为空，且 ID 不能重复')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$categoryLabel创建成功')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final selected = _provider.selectedContact;
        final isCompact = MediaQuery.of(context).size.width < 900;
        return Scaffold(
          appBar: AppBar(
            title: Text(selected == null
                ? 'Chat Demo'
                : 'Chat Demo - ${selected.name}'),
            actions: [
              IconButton(
                onPressed: _openCreateContactDialog,
                tooltip: '创建对象',
                icon: const Icon(Icons.person_add_alt_1),
              ),
              IconButton(
                onPressed: _openApiSettingDialog,
                tooltip: 'API 配置',
                icon: const Icon(Icons.key_outlined),
              ),
              IconButton(
                onPressed: _provider.toggleDebugMode,
                tooltip: '切换调试模式',
                icon: Icon(_provider.isDebugMode
                    ? Icons.bug_report
                    : Icons.bug_report_outlined),
              ),
            ],
          ),
          body: isCompact
              ? _buildMobileLayout(selected)
              : _buildDesktopLayout(selected),
        );
      },
    );
  }

  Future<void> _deleteContact(String contactId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此角色吗？所有聊天记录也将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _provider.deleteContact(contactId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角色已删除')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  /// 处理联系人选择
  ///
  /// 选择联系人后滚动聊天栏到最底部
  void _onSelectContact(String contactId) {
    _provider.selectContact(contactId);
    // 延迟执行滚动，等待UI更新完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Widget _buildDesktopLayout(Contact? selected) {
    return Row(
      children: [
        _ContactSidebar(
          contacts: _provider.contacts,
          selectedContactId: _provider.selectedContactId,
          onSelect: _onSelectContact,
          onAdd: _openCreateContactDialog,
          onDelete: _deleteContact,
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _buildChatArea(selected),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(Contact? selected) {
    return Scaffold(
      drawer: Drawer(
        child: _ContactSidebar(
          contacts: _provider.contacts,
          selectedContactId: _provider.selectedContactId,
          onSelect: (id) {
            _onSelectContact(id);
            Navigator.of(context).pop();
          },
          onAdd: () {
            Navigator.of(context).pop();
            _openCreateContactDialog();
          },
          onDelete: (id) {
            Navigator.of(context).pop();
            _deleteContact(id);
          },
        ),
      ),
      body: _buildChatArea(selected),
    );
  }

  Widget _buildChatArea(Contact? selected) {
    return Column(
      children: [
        if (_provider.connectionStatus == ConnectionStatus.reconnecting)
          Container(
            width: double.infinity,
            color: Colors.orange.shade100,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: const Text(
              '连接断开，正在重试...',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        if (selected == null)
          const Expanded(child: Center(child: Text('暂无对象，请先创建')))
        else
          Expanded(
            child: _provider.messages.isEmpty
                ? const Center(child: Text('开始聊天吧'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    itemCount: _provider.messages.length +
                        (_provider.isTyping ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (_provider.isTyping &&
                          index == _provider.messages.length) {
                        return const _TypingBubble();
                      }
                      final m = _provider.messages[index];
                      return _MessageBubble(message: m);
                    },
                  ),
          ),
        if (_provider.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _provider.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 6,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: selected == null ? '请先创建对象' : '输入消息...',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _provider.isLoading || selected == null ? null : _send,
                child: const Text('发送'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApiConfigDraft {
  const _ApiConfigDraft({
    required this.apiKey,
    required this.systemPrompt,
  });

  final String apiKey;
  final String systemPrompt;
}

class _ContactDraft {
  const _ContactDraft({
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

  bool get isJsonMode => jsonString != null && jsonString!.trim().isNotEmpty;

  bool get isNaturalLanguageMode =>
      naturalLanguage != null && naturalLanguage!.trim().isNotEmpty;
}

class _ContactEditorDialog extends StatefulWidget {
  const _ContactEditorDialog();

  @override
  State<_ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<_ContactEditorDialog> {
  int _selectedType = 0; // 0: 联系人, 1: 故事, 2: 助手
  int _selectedTab = 0;
  int _storyTab = 0; // 故事类型的输入方式选择
  bool _isConverting = false;

  // ========== 联系人表单模式控制器 ==========
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _avatarCtrl = TextEditingController();
  final TextEditingController _personalityCtrl = TextEditingController();
  final TextEditingController _appearanceCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();

  final List<String> _personality = <String>[];
  final List<String> _appearance = <String>[];
  final List<String> _backgroundStory = <String>[];

  // 联系人JSON模式控制器
  final TextEditingController _jsonCtrl = TextEditingController();

  // 联系人自然语言模式控制器
  final TextEditingController _naturalLanguageCtrl = TextEditingController();

  // ========== 故事表单模式控制器 ==========
  final TextEditingController _storyNameCtrl = TextEditingController();
  final TextEditingController _storyIdCtrl = TextEditingController();
  final TextEditingController _storyAvatarCtrl = TextEditingController();
  final TextEditingController _storyPersonalityCtrl = TextEditingController();
  final TextEditingController _storyBackgroundCtrl = TextEditingController();

  // 故事设定（key-value）
  final TextEditingController _storySettingKeyCtrl = TextEditingController();
  final TextEditingController _storySettingValueCtrl = TextEditingController();
  final TextEditingController _storySettingRelateCtrl = TextEditingController();

  final List<String> _storyPersonality = <String>[];
  final List<Map<String, dynamic>> _storySettings = <Map<String, dynamic>>[];
  final List<String> _storyBackgroundStory = <String>[];

  // 故事JSON模式控制器
  final TextEditingController _storyJsonCtrl = TextEditingController();

  // 故事自然语言模式控制器
  final TextEditingController _storyNaturalLanguageCtrl =
      TextEditingController();

  @override
  void dispose() {
    // 联系人控制器
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _avatarCtrl.dispose();
    _personalityCtrl.dispose();
    _appearanceCtrl.dispose();
    _backgroundCtrl.dispose();
    _jsonCtrl.dispose();
    _naturalLanguageCtrl.dispose();
    // 故事控制器
    _storyNameCtrl.dispose();
    _storyIdCtrl.dispose();
    _storyAvatarCtrl.dispose();
    _storyPersonalityCtrl.dispose();
    _storyBackgroundCtrl.dispose();
    _storySettingKeyCtrl.dispose();
    _storySettingValueCtrl.dispose();
    _storySettingRelateCtrl.dispose();
    _storyJsonCtrl.dispose();
    _storyNaturalLanguageCtrl.dispose();
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
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
    editCtrl.dispose();
    if (value == null || value.trim().isEmpty) return;
    setState(() => items[index] = value.trim());
  }

  void _addStorySetting() {
    final key = _storySettingKeyCtrl.text.trim();
    final value = _storySettingValueCtrl.text.trim();
    final relate = _storySettingRelateCtrl.text.trim();
    if (key.isEmpty || value.isEmpty) return;

    final relateItems = relate
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() {
      _storySettings.add({
        'key': key,
        'value': value,
        'relate': relateItems,
      });
      _storySettingKeyCtrl.clear();
      _storySettingValueCtrl.clear();
      _storySettingRelateCtrl.clear();
    });
  }

  Future<void> _editStorySetting(int index) async {
    final setting = _storySettings[index];
    final keyCtrl = TextEditingController(text: setting['key']);
    final valueCtrl = TextEditingController(text: setting['value']);
    final relateCtrl = TextEditingController(
        text: (setting['relate'] as List<String>).join('\n'));

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改设定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: '关键词'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: valueCtrl,
                decoration: const InputDecoration(labelText: '描述'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: relateCtrl,
                decoration: const InputDecoration(
                  labelText: '关联词条（每行一个）',
                  hintText: '(魔法师)\n(魔法石)',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop({
                'key': keyCtrl.text,
                'value': valueCtrl.text,
                'relate': relateCtrl.text,
              }),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    keyCtrl.dispose();
    valueCtrl.dispose();
    relateCtrl.dispose();

    if (result == null) return;

    final key = result['key']?.trim();
    final value = result['value']?.trim();
    if (key == null || value == null || key.isEmpty || value.isEmpty) return;

    final relateItems = (result['relate'] as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() {
      _storySettings[index] = {
        'key': key,
        'value': value,
        'relate': relateItems,
      };
    });
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

  Widget _buildFormContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: '对象名称'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _idCtrl,
          decoration: const InputDecoration(labelText: '对象 ID'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _avatarCtrl,
          decoration: const InputDecoration(labelText: '头像/简称'),
        ),
        const SizedBox(height: 12),
        _buildArrayEditor(
          title: '性格',
          hint: '例如：理性、温柔',
          items: _personality,
          controller: _personalityCtrl,
        ),
        const SizedBox(height: 12),
        _buildArrayEditor(
          title: '外貌',
          hint: '例如：长发、皮肤光滑',
          items: _appearance,
          controller: _appearanceCtrl,
        ),
        const SizedBox(height: 12),
        _buildArrayEditor(
          title: '背景故事',
          hint: '例如：在海边长大',
          items: _backgroundStory,
          controller: _backgroundCtrl,
        ),
      ],
    );
  }

  Widget _buildJsonContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'JSON 格式示例：',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '{\n'
            '  "id": "character-001",\n'
            '  "name": "阿星",\n'
            '  "avatar": "⭐",\n'
            '  "personality": ["直接", "理性"],\n'
            '  "appearance": ["黑色外套", "短发"],\n'
            '  "backgroundStory": ["与用户共同调查旧城区谜案"],\n'
            '  "worldKnowledge": ["旧城区夜里常停电"],\n'
            '  "selfKnowledge": ["擅长记录线索"],\n'
            '  "userKnowledge": ["用户喜欢先看证据"],\n'
            '  "belongings": ["手电筒", "笔记本"],\n'
            '  "status": ["健康"],\n'
            '  "mood": "专注",\n'
            '  "time": "晚上8点"\n'
            '}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _jsonCtrl,
          maxLines: 10,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: '在此粘贴 JSON...',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildNaturalLanguageContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '用自然语言描述角色：',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '示例：\n'
            '创建一个名叫阿星的侦探，性格理性冷静，穿着黑色外套，'
            '擅长记录线索，正在调查旧城区的谜案。他随身携带手电筒和笔记本。',
            style: TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _naturalLanguageCtrl,
          maxLines: 8,
          minLines: 4,
          decoration: const InputDecoration(
            hintText: '在此输入角色描述...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (_isConverting)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final text = _naturalLanguageCtrl.text.trim();
                if (text.isEmpty) return;
                setState(() => _isConverting = true);
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('AI 转换为 JSON'),
            ),
          ),
      ],
    );
  }

  // ==================== 故事类型表单 ====================

  Widget _buildStoryFormContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _storyNameCtrl,
          decoration: const InputDecoration(labelText: '故事名称'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _storyIdCtrl,
          decoration: const InputDecoration(labelText: '故事 ID'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _storyAvatarCtrl,
          decoration: const InputDecoration(labelText: '图标/简称'),
        ),
        const SizedBox(height: 12),
        _buildArrayEditor(
          title: '风格',
          hint: '例如：悬疑、奇幻',
          items: _storyPersonality,
          controller: _storyPersonalityCtrl,
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设定', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _storySettingKeyCtrl,
                    decoration: const InputDecoration(labelText: '关键词'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _storySettingValueCtrl,
              decoration: const InputDecoration(labelText: '描述'),
              maxLines: 3,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _storySettingRelateCtrl,
              decoration: const InputDecoration(
                labelText: '关联词条（每行一个）',
                hintText: '(魔法师)\n(魔法石)',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: _addStorySetting,
              child: const Text('添加设定'),
            ),
            const SizedBox(height: 6),
            if (_storySettings.isEmpty)
              const Text('暂无设定', style: TextStyle(color: Colors.grey))
            else
              Column(
                children: [
                  for (var i = 0; i < _storySettings.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _storySettings[i]['key'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => _editStorySetting(i),
                                    icon: const Icon(Icons.edit),
                                    tooltip: '编辑',
                                  ),
                                  IconButton(
                                    onPressed: () => setState(
                                        () => _storySettings.removeAt(i)),
                                    icon: const Icon(Icons.delete),
                                    tooltip: '删除',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(_storySettings[i]['value']),
                          if ((_storySettings[i]['relate'] as List<String>)
                              .isNotEmpty)
                            Column(
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                    '关联：${(_storySettings[i]['relate'] as List<String>).join(' ')}'),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        _buildArrayEditor(
          title: '背景故事',
          hint: '例如：王国陷入危机',
          items: _storyBackgroundStory,
          controller: _storyBackgroundCtrl,
        ),
      ],
    );
  }

  Widget _buildStoryJsonContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'JSON 格式示例：',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '{\n'
            '  "id": "story-001",\n'
            '  "name": "迷雾之城",\n'
            '  "avatar": "🏰",\n'
            '  "personality": ["悬疑", "黑暗"],\n'
            '  "settings": [\n'
            '    {\n'
            '      "key": "魔法",\n'
            '      "value": "这片大陆的魔法基于一个叫魔法石的特殊物质。是魔法石被激发产生的能量",\n'
            '      "relate": ["(魔法师)", "(魔法石)"]\n'
            '    },\n'
            '    {\n'
            '      "key": "缇娜",\n'
            '      "value": "小有天赋的魔法师",\n'
            '      "relate": ["(魔法师)", "(小白)"]\n'
            '    },\n'
            '    {\n'
            '      "key": "小白",\n'
            '      "value": "一只兔子，缇娜的宠物",\n'
            '      "relate": ["(缇娜)"]\n'
            '    }\n'
            '  ],\n'
            '  "backgroundStory": ["城市被神秘迷雾笼罩"],\n'
            '  "worldKnowledge": ["迷雾中隐藏着秘密"],\n'
            '  "selfKnowledge": ["故事有多个结局"],\n'
            '  "userKnowledge": ["用户是主角"],\n'
            '  "belongings": ["地图", "指南针"],\n'
            '  "status": ["进行中"],\n'
            '  "mood": "神秘",\n'
            '  "time": "深夜"\n'
            '}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _storyJsonCtrl,
          maxLines: 10,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: '在此粘贴 JSON...',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildStoryNaturalLanguageContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '用自然语言描述故事：',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '示例：\n'
            '创建一个名为"迷雾之城"的悬疑故事，设定在维多利亚时代的伦敦，'
            '城市被神秘的迷雾笼罩，隐藏着不为人知的秘密。用户将扮演侦探角色，'
            '揭开迷雾背后的真相。',
            style: TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _storyNaturalLanguageCtrl,
          maxLines: 8,
          minLines: 4,
          decoration: const InputDecoration(
            hintText: '在此输入故事描述...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (_isConverting)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final text = _storyNaturalLanguageCtrl.text.trim();
                if (text.isEmpty) return;
                setState(() => _isConverting = true);
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('AI 转换为 JSON'),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaceholderContent() {
    final typeLabels = ['联系人', '故事', '助手'];
    final typeDescriptions = [
      '创建一个可以对话的角色，包含性格、外貌、背景故事等属性。',
      '创建一个互动故事，用户可以作为主角参与其中。',
      '创建一个智能助手，帮助用户完成特定任务。',
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 40),
        Icon(
          _selectedType == 1 ? Icons.book : Icons.smart_toy,
          size: 64,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 16),
        Text(
          typeLabels[_selectedType],
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          typeDescriptions[_selectedType],
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '此功能正在开发中，敬请期待',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final typeLabels = ['联系人', '故事', '助手'];
    final typeIcons = [Icons.person, Icons.book, Icons.smart_toy];

    return AlertDialog(
      title: const Text('新建'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 类型选择器
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < typeLabels.length; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(typeLabels[i]),
                    icon: Icon(typeIcons[i], size: 18),
                  ),
              ],
              selected: <int>{_selectedType},
              onSelectionChanged: (value) {
                setState(() => _selectedType = value.first);
              },
            ),
            const SizedBox(height: 16),
            // 联系人和故事类型显示输入方式选择
            if (_selectedType == 0 || _selectedType == 1) ...[
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('表单')),
                  ButtonSegment(value: 1, label: Text('JSON')),
                  ButtonSegment(value: 2, label: Text('自然语言')),
                ],
                selected: <int>{_selectedType == 0 ? _selectedTab : _storyTab},
                onSelectionChanged: (value) {
                  setState(() {
                    if (_selectedType == 0) {
                      _selectedTab = value.first;
                    } else {
                      _storyTab = value.first;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
            ],
            Flexible(
              child: SingleChildScrollView(
                child: _selectedType == 0
                    ? (_selectedTab == 0
                        ? _buildFormContent()
                        : _selectedTab == 1
                            ? _buildJsonContent()
                            : _buildNaturalLanguageContent())
                    : _selectedType == 1
                        ? (_storyTab == 0
                            ? _buildStoryFormContent()
                            : _storyTab == 1
                                ? _buildStoryJsonContent()
                                : _buildStoryNaturalLanguageContent())
                        : _buildPlaceholderContent(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        // 联系人 - 表单
        if (_selectedType == 0 && _selectedTab == 0)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ContactDraft(
                  name: _nameCtrl.text,
                  id: _idCtrl.text,
                  avatar: _avatarCtrl.text,
                  personality: List<String>.from(_personality),
                  appearance: List<String>.from(_appearance),
                  settings: null,
                  backgroundStory: List<String>.from(_backgroundStory),
                  category: ContactCategory.contact,
                ),
              );
            },
            child: const Text('完成'),
          )
        // 联系人 - JSON
        else if (_selectedType == 0 && _selectedTab == 1)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ContactDraft(
                  name: '',
                  id: '',
                  avatar: '',
                  personality: const <String>[],
                  appearance: const <String>[],
                  settings: null,
                  backgroundStory: const <String>[],
                  category: ContactCategory.contact,
                  jsonString: _jsonCtrl.text,
                ),
              );
            },
            child: const Text('从JSON创建'),
          )
        // 联系人 - 自然语言
        else if (_selectedType == 0 && _selectedTab == 2)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ContactDraft(
                  name: '',
                  id: '',
                  avatar: '',
                  personality: const <String>[],
                  appearance: const <String>[],
                  settings: null,
                  backgroundStory: const <String>[],
                  category: ContactCategory.contact,
                  naturalLanguage: _naturalLanguageCtrl.text,
                ),
              );
            },
            child: const Text('AI生成角色'),
          )
        // 故事 - 表单
        else if (_selectedType == 1 && _storyTab == 0)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ContactDraft(
                  name: _storyNameCtrl.text,
                  id: _storyIdCtrl.text,
                  avatar: _storyAvatarCtrl.text,
                  personality: List<String>.from(_storyPersonality),
                  settings: List<Map<String, dynamic>>.from(_storySettings),
                  backgroundStory: List<String>.from(_storyBackgroundStory),
                  category: ContactCategory.story,
                ),
              );
            },
            child: const Text('完成'),
          )
        // 故事 - JSON
        else if (_selectedType == 1 && _storyTab == 1)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ContactDraft(
                  name: '',
                  id: '',
                  avatar: '',
                  personality: const <String>[],
                  appearance: null,
                  settings: null,
                  backgroundStory: const <String>[],
                  category: ContactCategory.story,
                  jsonString: _storyJsonCtrl.text,
                ),
              );
            },
            child: const Text('从JSON创建'),
          )
        // 故事 - 自然语言
        else if (_selectedType == 1 && _storyTab == 2)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(
                _ContactDraft(
                  name: '',
                  id: '',
                  avatar: '',
                  personality: const <String>[],
                  appearance: null,
                  settings: null,
                  backgroundStory: const <String>[],
                  category: ContactCategory.story,
                  naturalLanguage: _storyNaturalLanguageCtrl.text,
                ),
              );
            },
            child: const Text('AI生成故事'),
          )
        // 助手 - 开发中
        else
          const FilledButton(
            onPressed: null,
            child: Text('开发中'),
          ),
      ],
    );
  }
}

class _ContactSidebar extends StatelessWidget {
  const _ContactSidebar({
    required this.contacts,
    required this.selectedContactId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  final List<Contact> contacts;
  final String? selectedContactId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;

  Future<void> _confirmDelete(BuildContext context, Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${contact.name}" 吗？此操作不可恢复，所有聊天记录也将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete(contact.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('创建对象'),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Text(
                      '暂无对象',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final c = contacts[index];
                      final isSelected = c.id == selectedContactId;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        leading: c.avatar.isNotEmpty
                            ? Text(c.avatar,
                                style: const TextStyle(fontSize: 20))
                            : const Icon(Icons.person_outline),
                        title: Text(
                          c.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: c.status.isNotEmpty
                            ? Text(
                                c.status.first,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              )
                            : null,
                        onTap: () => onSelect(c.id),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _confirmDelete(context, c),
                          tooltip: '删除',
                          color: Colors.red.shade400,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(message.content),
              const SizedBox(height: 4),
              Text(
                time,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Text('正在输入...'),
      ),
    );
  }
}
