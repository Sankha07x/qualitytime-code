import 'package:flutter/material.dart';

/// Fast, classy page transition: the new page slides in while the old page
/// moves back a little. Only moves pages (no fade, no clip, no scale).
class WaterTransitionsBuilder extends PageTransitionsBuilder {
  const WaterTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = animation
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Tween<Offset>(begin: const Offset(0.10, 0), end: Offset.zero));
    final leave = secondaryAnimation
        .drive(CurveTween(curve: Curves.easeOutCubic))
        .drive(Tween<Offset>(begin: Offset.zero, end: const Offset(-0.04, 0)));
    return SlideTransition(
      position: leave,
      child: SlideTransition(
        position: enter,
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

/// Soft bouncing scroll for every list, without the Android glow.
class WaterScrollBehavior extends MaterialScrollBehavior {
  const WaterScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}