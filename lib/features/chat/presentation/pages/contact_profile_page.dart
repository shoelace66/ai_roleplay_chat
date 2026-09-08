import 'package:flutter/material.dart';
import '../../../../core/presentation/widgets/frosted_surface.dart';
import '../../../../core/utils/avatar_image.dart';
import '../../data/models/contact.dart';
import '../../data/models/continuity_state.dart';
import '../../domain/providers/chat_provider.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/story_state_editor.dart';

class ContactProfilePage extends StatefulWidget {
  const ContactProfilePage(
      {super.key,
      required this.provider,
      required this.contact,
      this.pickAvatar});
  final ChatProvider provider;
  final Contact contact;
  final Future<String?> Function()? pickAvatar;
  @override
  State<ContactProfilePage> createState() => _ContactProfilePageState();
}

class _ContactProfilePageState extends State<ContactProfilePage> {
  late final Contact original = widget.contact.deepCopy();
  late final String? branchId;
  late final Map<String, TextEditingController> fields;
  late final Map<String, String> initialFieldTexts;
  late ContinuityState state = original.continuity;
  late String avatar = original.avatar;
  bool saving = false, picking = false, dirty = false;
  String? error;

  static const profileLists = {
    'personality': '性格',
    'appearance': '外貌',
    'personalInfo': '个人信息',
    'backgroundStory': '背景故事',
    'narrativeRules': '叙事规则',
    'otherCharacteristics': '其他特征',
  };
  static const memoryLists = {
    'worldKnowledge': '世界知识',
    'selfKnowledge': '自我认知',
    'userKnowledge': '用户认知',
    'belongings': '物品',
    'status': '其他状态',
  };

  @override
  void initState() {
    super.initState();
    branchId = widget.provider.activeConversationBranch?.id;
    final data = original.toJson();
    fields = {
      for (final key in [
        'name',
        'fixedInput',
        'voice',
        'mood',
        'time',
        ...profileLists.keys,
        ...memoryLists.keys
      ])
        key: TextEditingController(
            text: data[key] is List
                ? (data[key] as List).join('\n')
                : (data[key] ?? '').toString()),
    };
    initialFieldTexts = {
      for (final entry in fields.entries) entry.key: entry.value.text
    };
    for (final controller in fields.values) {
      controller.addListener(() {
        if (!dirty && mounted) setState(() => dirty = true);
      });
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> chooseAvatar() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final value = await (widget.pickAvatar ?? AvatarImage.pick)();
      if (value != null && mounted) {
        setState(() {
          avatar = value;
          dirty = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => error = e is FormatException ? e.message : '无法打开照片，请重试。');
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> leave() async {
    if (saving || picking) return;
    if (dirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('放弃未保存的修改？'),
                content: const Text('已保存的资料会保留。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('继续编辑')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('放弃修改')),
                ],
              ));
      if (discard != true || !mounted) return;
    }
    if (mounted) {
      setState(() => dirty = false);
      Navigator.pop(context);
    }
  }

  Future<void> save() async {
    if (fields['name']!.text.trim().isEmpty) {
      setState(() => error = '名字不能为空，请在“资料”中填写名字。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    final data = original.toJson();
    for (final entry in fields.entries) {
      if (entry.value.text == initialFieldTexts[entry.key]) continue;
      data[entry.key] = profileLists.containsKey(entry.key) ||
              memoryLists.containsKey(entry.key)
          ? entry.value.text
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
          : entry.value.text.trim();
    }
    data['avatar'] = avatar;
    data.remove('currentStates');
    data['continuity'] = state.toJson();
    data['settings'] = settings;
    final ok = await widget.provider.updateContactProfile(
      original: original,
      draft: Contact.fromJson(data),
      expectedBranchId: branchId,
    );
    if (!mounted) return;
    setState(() {
      saving = false;
      if (ok) {
        dirty = false;
      } else {
        error = widget.provider.error ?? '保存失败，请重试';
      }
    });
    if (ok) Navigator.pop(context, true);
  }

  late List<Map<String, dynamic>> settings =
      original.settings.map((s) => Map<String, dynamic>.from(s)).toList();

  Future<void> editSetting(int? index) async {
    final item = index == null ? <String, dynamic>{} : settings[index];
    var name = (item['key'] ?? '').toString();
    var value = (item['value'] ?? '').toString();
    var related =
        (item['relate'] is List ? item['relate'] as List : []).join('\n');
    String? validation;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(index == null ? '添加设定' : '编辑设定'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        initialValue: name,
                        onChanged: (s) => name = s,
                        decoration: InputDecoration(
                            labelText: '设定名称', errorText: validation)),
                    const SizedBox(height: 12),
                    TextFormField(
                        initialValue: value,
                        onChanged: (s) => value = s,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(labelText: '设定内容')),
                    const SizedBox(height: 12),
                    TextFormField(
                        initialValue: related,
                        onChanged: (s) => related = s,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: '关联词', helperText: '每行一项')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () {
                          if (name.trim().isEmpty) {
                            update(() => validation = '请填写名称');
                            return;
                          }
                          Navigator.pop(context, <String, dynamic>{
                            'key': name.trim(),
                            'value': value.trim(),
                            'relate': related
                                .split('\n')
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList()
                          });
                        },
                        child: const Text('完成')),
                  ],
                )));
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          settings.add(result);
        } else {
          settings[index] = result;
        }
        dirty = true;
      });
    }
  }

  Widget field(String key, String label, {bool list = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
            key: ValueKey('profile-$key'),
            controller: fields[key],
            minLines: lines,
            maxLines: list || lines > 1 ? 8 : 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
                labelText: label, helperText: list ? '每行一项，可修改或删除已有内容' : null)),
      );

  Widget group(String title, String subtitle, List<Widget> children,
      {bool glass = false}) {
    final content = Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            ...children,
          ],
        ));
    return glass
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FrostedSurface(child: content))
        : Card(child: content);
  }

  Widget page(String key, List<Widget> children) => AmbientBackdrop(
          child: SingleChildScrollView(
        key: PageStorageKey(key),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children))),
      ));

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !dirty && !saving && !picking,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) leave();
        },
        child: DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                    tooltip: '返回',
                    onPressed: leave,
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
                title: const Text('角色资料'),
                actions: [
                  Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton(
                          key: const ValueKey('save-contact-profile'),
                          onPressed: saving || picking ? null : save,
                          child: Text(saving ? '保存中…' : '保存')))
                ],
                bottom: const PreferredSize(
                    preferredSize: Size.fromHeight(56),
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TabBar(tabs: [
                          Tab(text: '资料'),
                          Tab(text: '状态'),
                          Tab(text: '记忆')
                        ]))),
              ),
              body: Column(children: [
                if (error != null)
                  MaterialBanner(
                      content: Text(error!),
                      leading: const Icon(Icons.info_outline_rounded),
                      actions: [
                        TextButton(
                            onPressed: () => setState(() => error = null),
                            child: const Text('关闭'))
                      ]),
                Expanded(
                    child: AbsorbPointer(
                        absorbing: saving,
                        child: TabBarView(children: [
                          page('profile-basics', [
                            group(
                                '身份与头像',
                                '让每段对话都有自己的样子',
                                [
                                  Center(
                                      child: Stack(
                                          alignment: Alignment.bottomRight,
                                          children: [
                                        ContactAvatar(
                                            avatar: avatar,
                                            name: fields['name']!.text,
                                            size: 96,
                                            onTap:
                                                picking ? null : chooseAvatar),
                                        IgnorePointer(
                                            child: CircleAvatar(
                                                radius: 15,
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                child: Icon(
                                                    Icons.camera_alt_rounded,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onPrimary,
                                                    size: 16))),
                                      ])),
                                  const SizedBox(height: 8),
                                  Wrap(
                                      alignment: WrapAlignment.center,
                                      children: [
                                        TextButton.icon(
                                            onPressed:
                                                picking ? null : chooseAvatar,
                                            icon: const Icon(
                                                Icons.photo_library_outlined,
                                                size: 18),
                                            label: Text(
                                                picking ? '正在读取…' : '选择照片')),
                                        if (avatar.isNotEmpty)
                                          TextButton(
                                              onPressed: picking
                                                  ? null
                                                  : () => setState(() {
                                                        avatar = '';
                                                        dirty = true;
                                                      }),
                                              child: const Text('移除头像')),
                                      ]),
                                  const Center(
                                      child: Text('支持 JPG / JPEG、PNG、WebP',
                                          style: TextStyle(fontSize: 12))),
                                  const SizedBox(height: 24),
                                  field('name', '名字'),
                                  field('voice', '音色 ID'),
                                ],
                                glass: true),
                            group('角色设定', '这些内容会作为角色的稳定设定', [
                              field('fixedInput', '固定输入', lines: 3),
                              for (final entry in profileLists.entries)
                                field(entry.key, entry.value,
                                    list: true, lines: 2),
                            ]),
                            group('关联设定', '设定内容与用于事件关联的词项', [
                              for (var i = 0; i < settings.length; i++)
                                ListTile(
                                    title: Text(
                                        (settings[i]['key'] ?? '').toString()),
                                    subtitle: Text(
                                        (settings[i]['value'] ?? '').toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    onTap: () => editSetting(i),
                                    trailing: IconButton(
                                        tooltip: '删除设定',
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: () => setState(() {
                                              settings.removeAt(i);
                                              dirty = true;
                                            }))),
                              TextButton.icon(
                                  onPressed: () => editSetting(null),
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加设定')),
                            ]),
                          ]),
                          page('profile-state', [
                            group('当前状态', '可修正当前值，并调整系统记录的内容与规则', [
                              StoryStateEditor(
                                  value: state,
                                  onChanged: (next) => setState(() {
                                        state = next;
                                        dirty = true;
                                      })),
                            ]),
                            group('其他属性', '已有数据中的情绪、时间与状态标签', [
                              field('mood', '情绪'),
                              field('time', '时间'),
                              field('status', '其他状态', list: true, lines: 2),
                            ]),
                          ]),
                          page('profile-memory', [
                            group('系统维护的记忆', '这里显示已保存的完整知识与物品，修改后会用于后续对话', [
                              for (final entry in memoryLists.entries
                                  .where((e) => e.key != 'status'))
                                field(entry.key, entry.value,
                                    list: true, lines: 3),
                            ]),
                          ]),
                        ]))),
              ]),
            )),
      );
}
