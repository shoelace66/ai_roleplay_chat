import 'dart:ui';
import 'package:flutter/material.dart';

/// A clipped, local blur. Keep long message lists on opaque surfaces.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({super.key, required this.child, this.radius = 28});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surface.withValues(alpha: dark ? .84 : .80),
                theme.colorScheme.surface.withValues(alpha: dark ? .66 : .60),
              ],
            ),
            border: Border.all(
                color: Colors.white.withValues(alpha: dark ? .12 : .72)),
          ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

/// Static ambient color under glass; no full-screen blur or animation.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF202A40), Color(0xFF151922), Color(0xFF222539)]
              : const [Color(0xFFE2EAFB), Color(0xFFF4F6FA), Color(0xFFEAE4F5)],
          stops: const [0, .52, 1],
        ),
      ),
      child: child,
    );
  }
}
