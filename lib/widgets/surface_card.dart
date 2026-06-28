import 'package:flutter/material.dart';
import '../utils/theme.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius,
    this.border,
    this.clip = Clip.none,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final BoxBorder? border;
  final Clip clip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius ?? AppTheme.radiusMd);
    final card = Container(
      padding: padding,
      margin: margin,
      clipBehavior: clip,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: br,
        border: border ?? Border.all(color: AppTheme.surface2, width: 1),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: br, child: card);
  }
}
