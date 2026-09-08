import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/services/contact_import_parser.dart';

/// Keeps the original draft visible until validation succeeds and the user has
/// reviewed any compatibility adjustments. No model calls are used for repair.
class ContactJsonPreviewDialog extends StatefulWidget {
  const ContactJsonPreviewDialog({
    super.key,
    required this.title,
    required this.source,
    this.fallback = const ContactImportFallback(),
  });

  final String title;
  final String source;
  final ContactImportFallback fallback;

  @override
  State<ContactJsonPreviewDialog> createState() =>
      _ContactJsonPreviewDialogState();
}

class _ContactJsonPreviewDialogState extends State<ContactJsonPreviewDialog> {
  static const _parser = ContactImportParser();
  late final TextEditingController _controller;
  final FocusNode _editorFocus = FocusNode();
  ContactImportResult? _result;
  bool _confirmedAdjustments = false;
  String? _copyStatus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.source);
    _result = _parser.parseDetailed(widget.source, fallback: widget.fallback);
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  ContactImportResult _validate() {
    final result =
        _parser.parseDetailed(_controller.text, fallback: widget.fallback);
    setState(() {
      _result = result;
      _confirmedAdjustments = false;
    });
    return result;
  }

  void _submit() {
    final alreadyReviewed = _result != null;
    final result = _result ?? _validate();
    if (!result.isSuccess) {
      final offset = result.errors.firstOrNull?.offset;
      if (offset != null) {
        _controller.selection = TextSelection.collapsed(
            offset: offset.clamp(0, _controller.text.length));
        _editorFocus.requestFocus();
      }
      return;
    }
    // A fresh validation must show adjustments before they can be accepted.
    if (result.issues.isNotEmpty &&
        (!alreadyReviewed || !_confirmedAdjustments)) {
      return;
    }
    Navigator.of(context).pop(result.normalizedJson);
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _controller.text));
      if (mounted) setState(() => _copyStatus = 'JSON 已复制');
    } catch (_) {
      if (mounted) setState(() => _copyStatus = '复制失败，可在输入框中全选复制');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height -
            media.viewInsets.bottom -
            media.padding.vertical -
            40)
        .clamp(180.0, 820.0);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('contact-json-preview-input'),
                  controller: _controller,
                  focusNode: _editorFocus,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13, height: 1.3),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'JSON 内容（可修改）',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => setState(() {
                    _result = null;
                    _confirmedAdjustments = false;
                    _copyStatus = null;
                  }),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                flex: 2,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        result == null
                            ? '内容已修改，请重新检查格式。'
                            : !result.isSuccess
                                ? '发现 ${result.errors.length} 处需要修改的问题；原文已保留。'
                                : '已识别：${result.data!.name}。${result.issues.isEmpty ? '格式检查通过。' : '请核对以下兼容处理和未导入字段。'}',
                        key: const ValueKey('contact-json-summary'),
                        style: TextStyle(
                            color: result != null && !result.isSuccess
                                ? theme.colorScheme.error
                                : null),
                      ),
                      if (result != null)
                        for (final issue in [
                          ...result.errors,
                          ...result.issues.where((item) => !item.isError)
                        ])
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SelectableText(
                              '${issue.isError ? '需修改' : '提示'} · ${issue.description}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: issue.isError
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                      if (result != null &&
                          result.isSuccess &&
                          result.issues.isNotEmpty)
                        CheckboxListTile(
                          key: const ValueKey(
                              'contact-json-confirm-adjustments'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('我已确认上述调整及未导入字段',
                              style: TextStyle(fontSize: 12)),
                          value: _confirmedAdjustments,
                          onChanged: (value) => setState(
                              () => _confirmedAdjustments = value ?? false),
                        ),
                      if (_copyStatus != null)
                        Text(_copyStatus!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消')),
                  TextButton(onPressed: _copy, child: const Text('复制')),
                  TextButton(onPressed: _validate, child: const Text('检查格式')),
                  FilledButton(
                    key: const ValueKey('contact-json-create'),
                    onPressed: result != null &&
                            result.isSuccess &&
                            result.issues.isNotEmpty &&
                            !_confirmedAdjustments
                        ? null
                        : _submit,
                    child: Text(result == null ? '检查并创建' : '使用该 JSON 创建'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
