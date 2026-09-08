import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../../../../core/utils/avatar_image.dart';

class ContactAvatar extends StatefulWidget {
  const ContactAvatar(
      {super.key,
      required this.avatar,
      required this.name,
      this.size = 44,
      this.onTap});
  final String avatar, name;
  final double size;
  final VoidCallback? onTap;

  @override
  State<ContactAvatar> createState() => _ContactAvatarState();
}

class _ContactAvatarState extends State<ContactAvatar> {
  late Uint8List? bytes = AvatarImage.decode(widget.avatar);

  @override
  void didUpdateWidget(ContactAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatar != widget.avatar) {
      bytes = AvatarImage.decode(widget.avatar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.avatar;
    final name = widget.name;
    final size = widget.size;
    final onTap = widget.onTap;
    final colors = Theme.of(context).colorScheme;
    final fallback = Center(
        child: Text(
      avatar.isNotEmpty && !avatar.startsWith('data:')
          ? avatar.characters.take(2).toString()
          : (name.isEmpty ? '·' : name.characters.first),
      style: TextStyle(
          fontSize: size * .4,
          fontWeight: FontWeight.w600,
          color: colors.primary),
    ));
    return Semantics(
      label: onTap == null ? '$name 的头像' : '编辑 $name 的资料',
      button: onTap != null,
      child: Material(
        color: colors.primaryContainer.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(size * .34),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
              dimension: size,
              child: bytes == null
                  ? fallback
                  : Image.memory(bytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => fallback)),
        ),
      ),
    );
  }
}
