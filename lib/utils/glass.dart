import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

/// Reusable frosted-glass surface. Set [blurOn] to false to turn all blur
/// off (the translucent look stays, and it is the cheapest on slow phones).
class Glass extends StatelessWidget {
  static const bool blurOn = true;

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color tint;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const Glass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 0,
    this.tint = Colors.black,
    this.opacity = 0.35,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withOpacity((opacity + 0.10).clamp(0.0, 1.0)),
            tint.withOpacity(opacity),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    Widget w = ClipRRect(clipBehavior: Clip.hardEdge,
      borderRadius: borderRadius,
      child: (blurOn && blur > 0)
          ? BackdropFilter(
              filter: ImageFilter.blur(
                  sigmaX: blur > 8 ? 8 : blur, sigmaY: blur > 8 ? 8 : blur),
              child: inner,
            )
          : inner,
    );
    w = RepaintBoundary(child: w);
    if (margin != null) w = Padding(padding: margin!, child: w);
    return w;
  }
}