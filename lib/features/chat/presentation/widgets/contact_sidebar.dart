import 'package:flutter/material.dart';

import '../../data/models/contact.dart';

class ContactSidebar extends StatelessWidget {
  const ContactSidebar({
    required this.contacts,
    required this.selectedContactId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    this.showDeleteInList = true,
    this.showDeleteInFooter = false,
  });

  final List<Contact> contacts;
  final String? selectedContactId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;
  final bool showDeleteInList;
  final bool showDeleteInFooter;

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

  Contact? get _selectedContact {
    if (selectedContactId == null) return null;
    try {
      return contacts.firstWhere((c) => c.id == selectedContactId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedContact;
    return SizedBox(
      width: 220,
      child: Column(
        children: [
          // 顶部标题栏
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            alignment: Alignment.centerLeft,
            child: Text(
              '对象列表',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const Divider(height: 1),
          // 联系人列表
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
                        trailing: showDeleteInList
                            ? IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _confirmDelete(context, c),
                                tooltip: '删除',
                                color: Colors.red.shade400,
                              )
                            : null,
                      );
                    },
                  ),
          ),
          // 底部操作按钮区域
          const Divider(height: 1),
          // 创建对象按钮（移到最底部）
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('创建对象'),
              ),
            ),
          ),
          // 删除按钮（在创建按钮上方）
          if (showDeleteInFooter) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: SizedBox(
                width: double.infinity,
                child: selected != null
                    ? OutlinedButton.icon(
                        onPressed: () => _confirmDelete(context, selected),
                        icon: Icon(Icons.delete_outline,
                            color: Colors.red.shade400, size: 18),
                        label: Text(
                          '删除 ${selected.name}',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.red.shade200),
                        ),
                      )
                    : const OutlinedButton(
                        onPressed: null,
                        child: Text('未选择对象'),
                      ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
