import 'package:flutter/material.dart';

/// Light slide transition used for every screen in the app.
/// Only moves the page (no fade, no clip, no scale) so glass blur stays smooth.
class WaterTransitionsBuilder extends PageTransitionsBuilder {
  const WaterTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = animation
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero));
    return SlideTransition(position: slide, child: child);
  }
}

/// Soft bouncing scroll for every list.
class WaterScrollBehavior extends MaterialScrollBehavior {
  const WaterScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}