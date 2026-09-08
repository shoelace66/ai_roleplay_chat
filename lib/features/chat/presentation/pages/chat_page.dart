import 'dart:async';

import 'package:flutter/material.dart';
import '../../domain/services/contact_import_parser.dart';
import '../widgets/contact_json_preview_dialog.dart';

import '../../../../app_router.dart';
import '../../../../core/data/models/provider_settings.dart';
import '../../../../core/presentation/pages/provider_settings_page.dart';
import '../../application/chat_media_controller.dart';
import '../../application/chat_view_state.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../domain/providers/chat_provider.dart';
import '../widgets/contact_sidebar.dart';
import '../widgets/contact_editor_dialog.dart';
import '../widgets/chat_actions.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_shell.dart';
import '../widgets/chat_status_views.dart';
import '../widgets/message_composer.dart';
import 'contact_profile_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.provider,
    this.mediaController,
  });

  final ChatProvider provider;
  final ChatMediaController? mediaController;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatProvider _provider;
  late final ChatMediaController _mediaController;
  late final bool _ownsMediaController;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _provider = widget.provider;
    _ownsMediaController = widget.mediaController == null;
    _mediaController =
        widget.mediaController ?? ChatMediaController(provider: _provider);
    _provider.addListener(_scrollToBottom);
    _mediaController.addListener(_onMediaChanged);
  }

  @override
  void dispose() {
    _mediaController.removeListener(_onMediaChanged);
    if (_ownsMediaController) _mediaController.dispose();
    _provider.removeListener(_scrollToBottom);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onMediaChanged() {
    if (mounted) setState(() {});
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

  Future<void> _openContactProfile() async {
    final contact = _provider.selectedContact;
    if (contact == null) return;
    if (_provider.isLoading) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先停止生成，再修改资料')));
      return;
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ContactProfilePage(provider: _provider, contact: contact),
    ));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('资料已保存')));
    }
  }

  /// 打开 API 提供商设置页（LLM / 生图 / TTS）
  Future<void> _openApiSettingDialog() async {
    final saved = await Navigator.of(context).push<ProviderSettings>(
      MaterialPageRoute<ProviderSettings>(
        settings: const RouteSettings(name: AppRoutes.providerSettings),
        builder: (_) => ProviderSettingsPage(
          initial: _provider.providerSettings,
        ),
      ),
    );
    if (saved == null) return;
    await _provider.saveProviderSettings(saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API 提供商配置已保存')),
    );
  }

  /// 旧版"系统提示词"独立编辑入口（保留做兜底）
  Future<void> _openSystemPromptDialog() async {
    final ctrl = TextEditingController(text: _provider.currentSystemPrompt);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('系统提示词'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctrl,
            minLines: 2,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '可选：定义全局系统提示词',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _provider.saveSystemPrompt(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('系统提示词已保存')),
    );
  }

  void _openMemoryArchive() {
    if (_provider.selectedContact == null) return;
    Navigator.of(context).pushNamed(AppRoutes.memoryArchive);
  }

  void _openBackupRestore() {
    Navigator.of(context).pushNamed(AppRoutes.backup);
  }

  void _openWorldBook() {
    if (_provider.selectedContact == null) return;
    Navigator.of(context).pushNamed(AppRoutes.worldBook);
  }

  void _openConversationTimeline() {
    if (_provider.selectedContact == null) return;
    Navigator.of(context).pushNamed(AppRoutes.timeline);
  }

  Future<void> _editAndRegenerateLastTurn() async {
    if (_provider.selectedContact?.category != ContactCategory.assistant) {
      final message = _provider.messages
          .where(
              (m) => m.role == MessageRole.user && !m.id.startsWith('debug-'))
          .lastOrNull;
      if (message != null) await _editMessage(message);
      return;
    }
    final original = _provider.lastTurnUserInput;
    if (original == null) return;
    var draft = original;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改上一轮并重新生成'),
        content: TextFormField(
          initialValue: draft,
          onChanged: (value) => draft = value,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            helperText: '旧回复及其记忆会先完整撤回，再用修改后的内容生成。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
    if (edited == null || edited.isEmpty) return;
    final ok = await _provider.regenerateLastTurn(editedInput: edited);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已重新生成上一轮' : '重新生成失败')),
    );
  }

  Future<void> _createBranchFromMessage(Message message) async {
    final checkpoint = _provider.conversationCheckpoints
        .where((item) => item.sourceMessageId == message.id)
        .firstOrNull;
    if (checkpoint == null) return;
    final controller = TextEditingController(text: '从此处改写');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建剧情分支'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '分支名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建并切换'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final ok = await _provider.createBranchFromCheckpoint(
      checkpoint.id,
      name: name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已创建并切换到新分支' : '创建分支失败')),
    );
    if (ok) _scrollToBottom();
  }

  void _quoteMessage(Message message) {
    final quoted =
        message.content.split('\n').map((line) => '> $line').join('\n');
    _inputController.text = '$quoted\n\n';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
  }

  Future<void> _resendMessage(Message message) async {
    final id = _provider.selectedContactId;
    if (id == null) return;
    if (_provider.selectedContact?.category == ContactCategory.assistant) {
      await _provider.resendMessage(id, message.id);
      return;
    }
    final target = await _provider.previewDeleteMessage(message.id);
    if (target == null || !mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('重发本轮'),
              content: Text('将撤销本轮及后续共 ${target.turnCount} 轮对话和记忆，再用原输入重新生成。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('重发'))
              ],
            ));
    if (confirmed == true) {
      await _provider.resendStoryFrom(target, target.input);
    }
  }

  Future<void> _editMessage(Message message) async {
    final story =
        _provider.selectedContact?.category != ContactCategory.assistant &&
            message.role == MessageRole.user;
    final target =
        story ? await _provider.previewDeleteMessage(message.id) : null;
    if (!mounted || (story && target == null)) return;
    var draft = message.content;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(story ? '修改后重发（撤销 ${target!.turnCount} 轮）' : '编辑消息'),
        content: TextFormField(
          initialValue: draft,
          onChanged: (value) => draft = value,
          autofocus: true,
          minLines: 2,
          maxLines: 10,
          decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: story ? '将先恢复到本轮之前，再使用新输入生成。' : null,
              helperMaxLines: 2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft.trim()),
            child: Text(story ? '修改并重发' : '保存'),
          ),
        ],
      ),
    );
    if (edited == null || edited.isEmpty) return;
    if (story) {
      await _provider.resendStoryFrom(target!, edited);
    } else {
      await _provider.editMessage(message.id, edited);
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final story =
        _provider.selectedContact?.category != ContactCategory.assistant;
    final target =
        story ? await _provider.previewDeleteMessage(message.id) : null;
    if (!mounted || (story && target == null)) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(story ? '删除本轮及之后内容' : '删除消息'),
              content: Text(story
                  ? '将撤销 ${target!.turnCount} 轮对话及之后的状态修改，消息和记忆一起恢复到本轮之前。其他分支不受影响。'
                  : '这条消息将从当前会话删除。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('删除'))
              ],
            ));
    if (confirmed == true) {
      if (story) {
        await _provider.deleteStoryFrom(target!);
      } else {
        await _provider.deleteMessage(message.id);
      }
    }
  }

  Future<void> _generateCandidate(Message message) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在生成候选回复…')),
    );
    final ok = await _provider.generateReplyCandidate(message.id);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '候选回复已生成' : '未能生成不同的候选回复')),
    );
  }

  Future<void> _showCandidates(Message message) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择候选回复'),
        children: [
          for (final candidate in message.alternatives)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, candidate),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(candidate),
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      await _provider.applyReplyCandidate(message.id, selected);
    }
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
        ).showSnackBar(
            SnackBar(content: Text(_provider.error ?? 'AI 转换失败，请稍后重试')));
        return;
      }

      final reviewed = await _previewGeneratedJson(
        categoryLabel: categoryLabel,
        generatedJson: jsonStr,
        draft: result,
      );
      if (reviewed == null) return;

      // 使用转换后的 JSON 创建，合并表单中填写的字段
      final ok = await _provider.addContactFromJsonWithFallback(
        reviewed,
        category: result.category,
        fallbackName: result.name.isNotEmpty ? result.name : null,
        fallbackAvatar: result.avatar.isNotEmpty ? result.avatar : null,
        fallbackFixedInput:
            result.fixedInput.isNotEmpty ? result.fixedInput : null,
        fallbackCurrentStates: result.currentStates,
        fallbackContinuity: result.continuity,
        fallbackVoice: result.voice,
      );
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_provider.error ?? '创建未完成，请稍后重试')),
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
      final reviewed = await _previewGeneratedJson(
        categoryLabel: '$categoryLabel（JSON）',
        generatedJson: result.jsonString!,
        draft: result,
      );
      if (reviewed == null) return;

      // 使用 JSON 创建，合并表单中填写的字段作为后备
      final ok = await _provider.addContactFromJsonWithFallback(
        reviewed,
        category: result.category,
        fallbackName: result.name.isNotEmpty ? result.name : null,
        fallbackAvatar: result.avatar.isNotEmpty ? result.avatar : null,
        fallbackFixedInput:
            result.fixedInput.isNotEmpty ? result.fixedInput : null,
        fallbackCurrentStates: result.currentStates,
        fallbackContinuity: result.continuity,
        fallbackVoice: result.voice,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
            SnackBar(content: Text(_provider.error ?? '创建未完成，请稍后重试')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$categoryLabel创建成功')));
    } else {
      final ok = await _provider.addContact(
        name: result.name,
        avatar: result.avatar,
        fixedInput: result.fixedInput,
        currentStates: result.currentStates,
        continuity: result.continuity,
        category: result.category,
        voice: result.voice,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败：名称不能为空')),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$categoryLabel创建成功')));
    }
  }

  Future<String?> _previewGeneratedJson({
    required String categoryLabel,
    required String generatedJson,
    required ContactDraft draft,
  }) =>
      showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ContactJsonPreviewDialog(
          title: '$categoryLabel JSON（检查并创建）',
          source: generatedJson,
          fallback: ContactImportFallback(
            name: draft.name,
            avatar: draft.avatar,
            fixedInput: draft.fixedInput,
            currentStates: draft.currentStates,
            continuity: draft.continuity,
            voice: draft.voice,
          ),
        ),
      );
  Future<void> _recallLastTurn() async {
    if (!_provider.canRecall) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认撤回'),
        content: const Text('确定要撤回最近一轮对话吗？这将恢复角色到对话前的记忆状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _provider.recallLastTurn();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已撤回最近一轮对话' : '撤回失败')),
    );
  }

  ChatActions _buildActions({required bool compact, required bool hasContact}) {
    return ChatActions(
      compact: compact,
      hasContact: hasContact,
      canRecall: _provider.canRecall,
      debugMode: _provider.isDebugMode,
      onCreateContact: _openCreateContactDialog,
      onRecall: _recallLastTurn,
      onProviders: _openApiSettingDialog,
      onMemory: _openMemoryArchive,
      onTimeline: _openConversationTimeline,
      onSearch: () => Navigator.of(context).pushNamed(AppRoutes.search),
      onWorldBook: _openWorldBook,
      onImageGallery: () =>
          Navigator.of(context).pushNamed(AppRoutes.imageGallery),
      onBackup: _openBackupRestore,
      onSystemPrompt: _openSystemPromptDialog,
      onSettings: () => Navigator.of(context).pushNamed(AppRoutes.appSettings),
      onAssistantSettings: () =>
          Navigator.of(context).pushNamed(AppRoutes.assistantSettings),
      onToggleDebug: _provider.toggleDebugMode,
      profiles: _provider.llmProfiles,
      activeProfile: _provider.providerSettings.llm,
      onActivateProfile: _provider.activateLlmProfile,
      onCheckProfiles: _checkLlmProfiles,
    );
  }

  Future<void> _checkLlmProfiles() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在检查全部 LLM Profile…')),
    );
    final results = await _provider.checkLlmProfiles();
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LLM 健康检查'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in results.entries)
                ListTile(
                  leading: Icon(
                    entry.value == null ? Icons.check_circle : Icons.error,
                    color: entry.value == null ? Colors.green : Colors.red,
                  ),
                  title: Text('${entry.key.presetId} / ${entry.key.model}'),
                  subtitle: Text(entry.value ?? '连接正常'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        final state = _provider.state;
        final selected = state.selectedContact;
        final compact = MediaQuery.of(context).size.width < 900;
        return ChatShell(
          compact: compact,
          title: selected?.name ?? 'AI 角色对话',
          avatar: selected?.avatar ?? '',
          onEditProfile: selected == null ? null : _openContactProfile,
          actions: _buildActions(
            compact: compact,
            hasContact: selected != null,
          ),
          contactPanel: _buildContactPanel(compact, state),
          chatArea: _buildChatArea(state),
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
  Future<void> _onSelectContact(String contactId) async {
    await _provider.selectContact(contactId);
    if (!mounted) return;
    // 延迟执行滚动，等待UI更新完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _loadOlderMessages() async {
    if (!_scrollController.hasClients) {
      await _provider.loadOlderMessages();
      return;
    }
    final oldPixels = _scrollController.position.pixels;
    final oldMaxExtent = _scrollController.position.maxScrollExtent;
    final loaded = await _provider.loadOlderMessages();
    if (!mounted || !loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final addedExtent =
          _scrollController.position.maxScrollExtent - oldMaxExtent;
      _scrollController.jumpTo(
        (oldPixels + addedExtent).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  /// 长按 AI 消息 → 生成图片
  ///
  /// 完整流程：
  /// 1. 弹一个描述输入框（预填原文，可改写）
  /// 2. 静默调用 LLM 润色：把"用户中文描述 + 联系人设定"扩写为
  ///    结构化英文生图 prompt
  /// 3. 弹一个「生图中…」SnackBar（不阻塞 UI）
  /// 4. 调用生图服务
  /// 5. 把结果作为新的图片消息插入到消息流末尾，
  ///    同时保留 `originalPrompt`（用户原文）和 `imagePrompt`（润色后）
  Future<void> _generateImageForMessage(Message source) async {
    final userPrompt = await _promptForImageDescription(source.content);
    if (userPrompt == null || !mounted) return;
    final contactId = _provider.selectedContactId;
    if (contactId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('生图中…（正在根据角色设定润色描述）')),
    );
    final result = await _mediaController.generateImage(
      contactId: contactId,
      userPrompt: userPrompt,
    );
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess ? '图片已添加到会话' : '生图失败：${result.error}',
        ),
      ),
    );
    if (result.isSuccess) _scrollToBottom();
  }

  Future<String?> _promptForImageDescription(String defaultText) async {
    final ctrl = TextEditingController(text: defaultText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成图片'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '用中文描述你想要的画面，提交后会自动根据当前角色设定翻译为英文 prompt。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '描述你想生成的图片',
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
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// 朗读 AI 消息文本
  ///
  /// - 当前在播放同一条消息：忽略（实际通过 stop 按钮触发）
  /// - 当前在播放其他消息：先停掉旧的，再播新的
  /// - 没选联系人 / 文本为空：忽略
  Future<void> _speakMessage(Message message) =>
      _mediaController.speak(message);

  Future<void> _stopSpeaking() => _mediaController.stopSpeaking();

  Widget _buildContactPanel(bool compact, ChatViewState state) {
    return ContactSidebar(
      contacts: state.contacts,
      selectedContactId: state.selectedContactId,
      onEdit: (id) async {
        if (compact) Navigator.of(context).pop();
        await _provider.selectContact(id);
        if (mounted && _provider.selectedContactId == id) {
          await _openContactProfile();
        }
      },
      onSelect: compact
          ? (id) {
              _onSelectContact(id);
              Navigator.of(context).pop();
            }
          : _onSelectContact,
      onAdd: compact
          ? () {
              Navigator.of(context).pop();
              _openCreateContactDialog();
            }
          : _openCreateContactDialog,
      onDelete: compact
          ? (id) {
              Navigator.of(context).pop();
              _deleteContact(id);
            }
          : _deleteContact,
      showDeleteInList: !compact,
      showDeleteInFooter: compact,
    );
  }

  Widget _buildChatArea(ChatViewState state) {
    final selected = state.selectedContact;
    return Column(
      children: [
        Expanded(
          child: selected == null || state.messages.isEmpty
              ? ChatEmptyState(hasContact: selected != null)
              : ChatMessageList(
                  protectContinuity: _provider.selectedContact?.category !=
                      ContactCategory.assistant,
                  messages: state.messages,
                  controller: _scrollController,
                  isTyping: state.isTyping,
                  hasOlderMessages: state.hasOlderMessages,
                  isLoadingOlderMessages: state.isLoadingOlderMessages,
                  totalMessageCount: state.totalMessageCount,
                  canRegenerateLastTurn: state.canRegenerateLastTurn,
                  onLoadOlder: _loadOlderMessages,
                  onRetry: _resendMessage,
                  onGenerateImage: _generateImageForMessage,
                  onRegenerate: _editAndRegenerateLastTurn,
                  canCreateBranch: (message) =>
                      _provider.conversationCheckpoints.any(
                    (checkpoint) => checkpoint.sourceMessageId == message.id,
                  ),
                  onCreateBranch: _createBranchFromMessage,
                  onSpeak: _speakMessage,
                  onStopSpeak: _stopSpeaking,
                  isSpeaking: _mediaController.isSpeaking,
                  assistantLabel: selected.name,
                  assistantAvatar: selected.avatar,
                  onEditProfile: _openContactProfile,
                  onEdit: _editMessage,
                  onDelete: _deleteMessage,
                  onQuote: _quoteMessage,
                  onGenerateCandidate: _generateCandidate,
                  onShowCandidates: _showCandidates,
                ),
        ),
        if (state.error != null) ChatErrorBanner(message: state.error!),
        MessageComposer(
          controller: _inputController,
          enabled: selected != null,
          isGenerating: state.isLoading,
          canCancel: state.canCancelGeneration,
          onSend: _send,
          onCancel: _provider.cancelGeneration,
        ),
      ],
    );
  }
}
