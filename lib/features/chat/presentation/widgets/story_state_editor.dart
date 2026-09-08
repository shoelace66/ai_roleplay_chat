import 'package:flutter/material.dart';
import '../../data/models/continuity_state.dart';

class StoryStateEditor extends StatelessWidget {
  const StoryStateEditor(
      {super.key, required this.value, required this.onChanged});
  final ContinuityState value;
  final ValueChanged<ContinuityState> onChanged;
  void replace(List<StateDefinition> definitions, Map<String, String> values) =>
      onChanged(ContinuityState(
          revision: value.revision, definitions: definitions, values: values));

  Future<void> edit(BuildContext context, StateDefinition? definition) async {
    final result = await showDialog<ContinuityState>(
        context: context,
        builder: (_) =>
            _DefinitionDialog(value: value, definition: definition));
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('需要记录的状态', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('由你定义记录内容和更新规则；未发生变化的值会持续保留。'),
        for (var i = 0; i < value.definitions.length; i++)
          Card(
              child: Column(children: [
            ListTile(
                title: Text(value.definitions[i].name),
                subtitle: Text(value.values[value.definitions[i].id] ??
                    value.definitions[i].initialValue),
                onTap: () => edit(context, value.definitions[i]),
                trailing: IconButton(
                    tooltip: '删除记录项',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final next = {...value.values}
                        ..remove(value.definitions[i].id);
                      replace([...value.definitions]..removeAt(i), next);
                    })),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(
                  tooltip: '上移',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: i == 0
                      ? null
                      : () {
                          final next = [...value.definitions];
                          final item = next.removeAt(i);
                          next.insert(i - 1, item);
                          replace(next, value.values);
                        }),
              IconButton(
                  tooltip: '下移',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: i == value.definitions.length - 1
                      ? null
                      : () {
                          final next = [...value.definitions];
                          final item = next.removeAt(i);
                          next.insert(i + 1, item);
                          replace(next, value.values);
                        }),
            ]),
          ])),
        TextButton.icon(
            onPressed: () => edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('添加记录项')),
      ]);
}

class _DefinitionDialog extends StatefulWidget {
  const _DefinitionDialog({required this.value, required this.definition});
  final ContinuityState value;
  final StateDefinition? definition;
  @override
  State<_DefinitionDialog> createState() => _DefinitionDialogState();
}

class _DefinitionDialogState extends State<_DefinitionDialog> {
  late final name = TextEditingController(text: widget.definition?.name ?? '');
  late final description =
      TextEditingController(text: widget.definition?.description ?? '');
  late final initial =
      TextEditingController(text: widget.definition?.initialValue ?? '');
  late final rule =
      TextEditingController(text: widget.definition?.updateRule ?? '');
  late final current = TextEditingController(
      text: widget.definition == null
          ? ''
          : widget.value.values[widget.definition!.id] ??
              widget.definition!.initialValue);
  String? error;
  @override
  void dispose() {
    for (final controller in [name, description, initial, rule, current]) {
      controller.dispose();
    }
    super.dispose();
  }

  void save() {
    final definition = widget.definition;
    final value = widget.value;
    if (name.text.trim().isEmpty ||
        value.definitions
            .any((d) => d.id != definition?.id && d.name == name.text.trim())) {
      setState(() => error = '名称不能为空或重复');
      return;
    }
    final id =
        definition?.id ?? 'state-${DateTime.now().microsecondsSinceEpoch}';
    final next = StateDefinition(
        id: id,
        name: name.text.trim(),
        description: description.text,
        initialValue: initial.text,
        updateRule: rule.text);
    Navigator.pop(
        context,
        ContinuityState(revision: value.revision, definitions: [
          for (final d in value.definitions)
            if (d.id == id) next else d,
          if (definition == null) next
        ], values: {
          ...value.values,
          id: definition == null ? initial.text : current.text
        }));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.definition == null ? '添加记录项' : '编辑记录项'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration:
                      InputDecoration(labelText: '名称', errorText: error)),
              TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: '记录说明', hintText: '需要持续保留哪些细节')),
              TextField(
                  controller: initial,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '初值（可留空）')),
              TextField(
                  controller: rule,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: '更新规则', hintText: '什么情况下改变，什么情况下必须保持')),
              if (widget.definition != null)
                TextField(
                    controller: current,
                    minLines: 1,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(labelText: '当前值（留空表示清空）')),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: save, child: const Text('保存'))
        ],
      );
}
