import 'package:flutter/material.dart';
import '../../../../core/presentation/widgets/frosted_surface.dart';

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isGenerating,
    required this.canCancel,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isGenerating;
  final bool canCancel;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = isGenerating ? onCancel : onSend;
    final actionEnabled = enabled && (!isGenerating || canCancel);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: FrostedSurface(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('message-composer-input'),
                    controller: controller,
                    enabled: enabled && !isGenerating,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      if (enabled && !isGenerating) onSend();
                    },
                    decoration: InputDecoration(
                      filled: false,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: enabled ? '输入消息…' : '请先创建对象',
                      hintStyle: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    key: const ValueKey('message-composer-action'),
                    onPressed: actionEnabled ? action : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      backgroundColor: isGenerating
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    icon: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Icon(
                          isGenerating
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          key: ValueKey(isGenerating),
                          size: 20),
                    ),
                    label: Text(isGenerating ? '停止' : '发送'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
