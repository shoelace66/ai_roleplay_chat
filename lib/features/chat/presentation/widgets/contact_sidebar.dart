import 'package:flutter/material.dart';
import '../../data/models/contact.dart';
import 'contact_avatar.dart';
import '../../../../core/presentation/widgets/frosted_surface.dart';

class ContactSidebar extends StatelessWidget {
  const ContactSidebar(
      {super.key,
      required this.contacts,
      required this.selectedContactId,
      required this.onSelect,
      required this.onAdd,
      required this.onDelete,
      this.onEdit,
      this.showDeleteInList = true,
      this.showDeleteInFooter = false});
  final List<Contact> contacts;
  final String? selectedContactId;
  final ValueChanged<String> onSelect, onDelete;
  final ValueChanged<String>? onEdit;
  final VoidCallback onAdd;
  final bool showDeleteInList, showDeleteInFooter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected =
        contacts.where((c) => c.id == selectedContactId).firstOrNull;
    return SizedBox(
        width: 300,
        child: FrostedSurface(
          child: SafeArea(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 20, 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('对话',
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          Text('${contacts.length} 个角色与故事',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ])),
                Expanded(
                    child: contacts.isEmpty
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                Icon(Icons.forum_outlined,
                                    size: 40, color: theme.colorScheme.primary),
                                const SizedBox(height: 16),
                                const Text('让故事从这里开始'),
                                const SizedBox(height: 6),
                                const Text('创建一个角色，开启一段对话',
                                    style: TextStyle(fontSize: 12)),
                              ]))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: contacts.length,
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              final active = contact.id == selectedContactId;
                              final current = contact.currentStates.entries
                                  .where((e) => e.value.trim().isNotEmpty)
                                  .firstOrNull;
                              final subtitle = current == null
                                  ? switch (contact.category) {
                                      ContactCategory.story => '故事 · 继续创作',
                                      ContactCategory.assistant => '助手 · 随时待命',
                                      ContactCategory.contact => '角色 · 开始对话',
                                    }
                                  : '${current.key} · ${current.value}';
                              return AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: active
                                      ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: .65)
                                      : theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  leading: ContactAvatar(
                                      avatar: contact.avatar,
                                      name: contact.name,
                                      onTap: onEdit == null
                                          ? null
                                          : () => onEdit!(contact.id)),
                                  title: Text(contact.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: active
                                              ? FontWeight.w700
                                              : FontWeight.w500)),
                                  subtitle: Text(subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant)),
                                  onTap: () => onSelect(contact.id),
                                  trailing: showDeleteInList
                                      ? IconButton(
                                          tooltip: '删除',
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 19),
                                          onPressed: () => onDelete(contact.id),
                                        )
                                      : null,
                                ),
                              );
                            })),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                              onPressed: onAdd,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('创建对象')),
                          if (showDeleteInFooter && selected != null)
                            TextButton.icon(
                                onPressed: () => onDelete(selected.id),
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 18, color: theme.colorScheme.error),
                                label: Text('删除 ${selected.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.colorScheme.error))),
                        ])),
              ])),
        ));
  }
}
