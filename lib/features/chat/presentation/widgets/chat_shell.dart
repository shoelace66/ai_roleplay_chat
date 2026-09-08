import 'package:flutter/material.dart';
import 'contact_avatar.dart';
import '../../../../core/presentation/widgets/frosted_surface.dart';

class ChatShell extends StatelessWidget {
  const ChatShell({
    super.key,
    required this.compact,
    required this.title,
    required this.actions,
    required this.contactPanel,
    required this.chatArea,
    this.avatar = '',
    this.onEditProfile,
  });

  final bool compact;
  final String title;
  final Widget actions;
  final Widget contactPanel;
  final Widget chatArea;
  final String avatar;
  final VoidCallback? onEditProfile;

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      titleSpacing: 0,
      title: Semantics(
        button: onEditProfile != null,
        label: '编辑角色资料',
        child: InkWell(
          key: const ValueKey('contact-header'),
          borderRadius: BorderRadius.circular(18),
          onTap: onEditProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (onEditProfile != null) ...[
                ContactAvatar(
                    avatar: avatar,
                    name: title,
                    size: 40,
                    onTap: onEditProfile),
                const SizedBox(width: 10),
              ],
              Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    if (onEditProfile != null)
                      Text('资料与状态',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  ])),
            ]),
          ),
        ),
      ),
      centerTitle: false,
      leading: compact
          ? Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: '打开对象列表',
              ),
            )
          : null,
      actions: [actions],
      elevation: 0,
      scrolledUnderElevation: 0,
    );
    if (compact) {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(
            width: 300,
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: contactPanel),
        body: AmbientBackdrop(child: chatArea),
        resizeToAvoidBottomInset: true,
      );
    }
    return Scaffold(
      appBar: appBar,
      body: AmbientBackdrop(
          child: Row(
        children: [
          contactPanel,
          const VerticalDivider(width: 1),
          Expanded(child: chatArea),
        ],
      )),
    );
  }
}
