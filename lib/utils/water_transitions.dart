import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Water-ripple page transition used for every screen in the app.
class WaterTransitionsBuilder extends PageTransitionsBuilder {
  const WaterTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 650);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 450);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = Cubic(0.22, 1.0, 0.36, 1.0);

    final scale = animation
        .drive(CurveTween(curve: curve))
        .drive(Tween<double>(begin: 0.94, end: 1.0));
    final fade = animation.drive(
      CurveTween(curve: const Interval(0.0, 0.55, curve: Curves.easeOut)),
    );
    final back = secondaryAnimation
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Tween<double>(begin: 1.0, end: 0.97));

    return ScaleTransition(
      scale: back,
      child: AnimatedBuilder(
        animation: animation,
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
        builder: (context, c) {
          final t =
              curve.transform(animation.value.clamp(0.0, 1.0).toDouble());
          return ClipPath(
            clipper: _RippleClipper(t),
            clipBehavior: t >= 1.0 ? Clip.none : Clip.antiAlias,
            child: c,
          );
        },
      ),
    );
  }
}

class _RippleClipper extends CustomClipper<Path> {
  final double t;
  _RippleClipper(this.t);

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height);
    final maxR = math.sqrt(size.width * size.width + size.height * size.height);
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: maxR * t));
  }

  @override
  bool shouldReclip(_RippleClipper old) => old.t != t;
}

/// Soft bouncing scroll for every list.
class WaterScrollBehavior extends MaterialScrollBehavior {
  const WaterScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}