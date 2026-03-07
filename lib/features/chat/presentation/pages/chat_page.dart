import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../domain/providers/chat_provider.dart';
import '../../domain/services/heartbeat_manager.dart';
import '../widgets/contact_sidebar.dart';
import '../widgets/contact_editor_dialog.dart';

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
    final promptCtrl = TextEditingController(
      text: _provider.currentSystemPrompt,
    );

    final result = await showDialog<ApiConfigDraft>(
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
                  ApiConfigDraft(
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('API 配置已保存')));
  }

  Future<void> _openCreateContactDialog() async {
    final result = await showDialog<ContactDraft>(
      context: context,
      builder: (context) => const ContactEditorDialog(),
    );
    if (result == null) return;

    final categoryLabel =
        result.category == ContactCategory.story ? '故事' : '角色';

    // 判断是否是自然语言模式
    if (result.isNaturalLanguageMode) {
      // 显示加载提示
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('正在使用 AI 生成$categoryLabel...')));
      }

      // 调用 LLM 转换
      final jsonStr = await _provider.convertNaturalLanguageToJson(
        result.naturalLanguage!,
        isStory: result.category == ContactCategory.story,
      );

      if (!mounted) return;

      if (jsonStr == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 转换失败，请检查描述或稍后重试')));
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI 生成$categoryLabel成功')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('创建失败：JSON 格式错误或 ID 已存在')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$categoryLabel创建成功')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$categoryLabel创建成功')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final selected = _provider.selectedContact;
        final isCompact = MediaQuery.of(context).size.width < 900;

        // 移动端使用独立Scaffold，桌面端使用嵌套布局
        if (isCompact) {
          return _buildMobileLayout(selected);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              selected == null ? 'Chat Demo' : selected.name,
            ),
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
                icon: Icon(
                  _provider.isDebugMode
                      ? Icons.bug_report
                      : Icons.bug_report_outlined,
                ),
              ),
            ],
          ),
          body: _buildDesktopLayout(selected),
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
        ContactSidebar(
          contacts: _provider.contacts,
          selectedContactId: _provider.selectedContactId,
          onSelect: _onSelectContact,
          onAdd: _openCreateContactDialog,
          onDelete: _deleteContact,
          showDeleteInList: true,
          showDeleteInFooter: false,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildChatArea(selected)),
      ],
    );
  }

  Widget _buildMobileLayout(Contact? selected) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selected == null ? '' : selected.name),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: '打开对象列表',
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openCreateContactDialog,
            tooltip: '创建对象',
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      drawer: Drawer(
        child: ContactSidebar(
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
          showDeleteInList: false,
          showDeleteInFooter: true,
        ),
      ),
      body: _buildChatArea(selected),
      resizeToAvoidBottomInset: true,
    );
  }

  Widget _buildChatArea(Contact? selected, {bool showAppBar = true}) {
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
                      horizontal: 10,
                      vertical: 12,
                    ),
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

class ApiConfigDraft {
  const ApiConfigDraft({required this.apiKey, required this.systemPrompt});

  final String apiKey;
  final String systemPrompt;
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
                    .bodySmall
                    ?.copyWith(color: Colors.grey.shade500),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDot(),
              _buildDot(delay: 150),
              _buildDot(delay: 300),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDot({int delay = 0}) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: Colors.grey,
        shape: BoxShape.circle,
      ),
      child: AnimatedOpacity(
        opacity: 0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        child: Container(),
      ),
    );
  }
}
