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

    keyCtrl.dispose();
    promptCtrl.dispose();

    if (result == null) return;
    await _provider.saveApiKey(result.apiKey);
    await _provider.saveSystemPrompt(result.systemPrompt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API 设置已保存')),
    );
  }

  Future<void> _openCreateContactDialog() async {
    final result = await showDialog<_ContactDraft>(
      context: context,
      builder: (context) => const _ContactEditorDialog(),
    );
    if (result == null) return;
    final ok = await _provider.addContact(
      name: result.name,
      contactId: result.id,
      avatar: result.avatar,
      personality: result.personality,
      appearance: result.appearance,
      backgroundStory: result.backgroundStory,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败：名称/ID 不能为空，且 ID 不能重复')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('对象创建成功')),
    );
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
                tooltip: _provider.isDebugMode ? '关闭调试' : '开启调试',
                icon: Icon(_provider.isDebugMode
                    ? Icons.bug_report
                    : Icons.bug_report_outlined),
              ),
              _ConnectionPill(status: _provider.connectionStatus),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: !isCompact
                ? Row(
                    children: [
                      _ContactSidebar(
                        contacts: _provider.contacts,
                        selectedContactId: _provider.selectedContactId,
                        onSelect: _provider.selectContact,
                        onAdd: _openCreateContactDialog,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildChatPane()),
                    ],
                  )
                : _buildChatPane(showTopContacts: true),
          ),
        );
      },
    );
  }

  Widget _buildChatPane({bool showTopContacts = false}) {
    final selected = _provider.selectedContact;
    return Column(
      children: [
        if (showTopContacts)
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: _provider.contacts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = _provider.contacts[i];
                final selectedStyle = c.id == _provider.selectedContactId;
                return ChoiceChip(
                  label: Text(c.name),
                  selected: selectedStyle,
                  onSelected: (_) => _provider.selectContact(c.id),
                );
              },
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

class _ContactSidebar extends StatelessWidget {
  const _ContactSidebar({
    required this.contacts,
    required this.selectedContactId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Contact> contacts;
  final String? selectedContactId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

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
                icon: const Icon(Icons.add),
                label: const Text('创建对象'),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, index) {
                final c = contacts[index];
                final selected = c.id == selectedContactId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  onTap: () => onSelect(c.id),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  tileColor: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  leading: CircleAvatar(child: Text(_avatarText(c))),
                  title: Text(c.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text(c.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _avatarText(Contact c) {
    final av = c.avatar.trim();
    if (av.isNotEmpty) return av.characters.first.toUpperCase();
    final name = c.name.trim();
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final connected = status == ConnectionStatus.connected;
    final label = connected ? '在线' : '重连中';
    final bg = connected ? Colors.green.shade100 : Colors.orange.shade100;
    final fg = connected ? Colors.green.shade900 : Colors.orange.shade900;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
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

class _ContactDraft {
  const _ContactDraft({
    required this.name,
    required this.id,
    required this.avatar,
    required this.personality,
    required this.appearance,
    required this.backgroundStory,
  });

  final String name;
  final String id;
  final String avatar;
  final List<String> personality;
  final List<String> appearance;
  final List<String> backgroundStory;
}

class _ContactEditorDialog extends StatefulWidget {
  const _ContactEditorDialog();

  @override
  State<_ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<_ContactEditorDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _avatarCtrl = TextEditingController();
  final TextEditingController _personalityCtrl = TextEditingController();
  final TextEditingController _appearanceCtrl = TextEditingController();
  final TextEditingController _backgroundCtrl = TextEditingController();

  final List<String> _personality = <String>[];
  final List<String> _appearance = <String>[];
  final List<String> _backgroundStory = <String>[];

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
      title: const Text('创建对象'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
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
          ),
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
              _ContactDraft(
                name: _nameCtrl.text,
                id: _idCtrl.text,
                avatar: _avatarCtrl.text,
                personality: List<String>.from(_personality),
                appearance: List<String>.from(_appearance),
                backgroundStory: List<String>.from(_backgroundStory),
              ),
            );
          },
          child: const Text('完成'),
        ),
      ],
    );
  }
}
