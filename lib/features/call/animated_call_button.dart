import 'package:flutter/material.dart';

/// Round call-screen button with animations:
/// press shrink, color fade when [highlighted] changes, and icon swap.
/// Dark translucent fill + border + shadow so it stays visible on any video.
class AnimatedCallButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;

  /// True = white button with dark icon (e.g. muted, camera off, speaker on).
  final bool highlighted;

  /// Fixed color (e.g. red for end call). Overrides [highlighted] colors.
  final Color? background;

  const AnimatedCallButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.highlighted = false,
    this.background,
  });

  @override
  State<AnimatedCallButton> createState() => _AnimatedCallButtonState();
}

class _AnimatedCallButtonState extends State<AnimatedCallButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ??
        (widget.highlighted
            ? Colors.white.withOpacity(0.92)
            : Colors.black.withOpacity(0.30));
    final fg = (widget.background == null && widget.highlighted)
        ? Colors.black
        : Colors.white;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.35)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              widget.icon,
              key: ValueKey(widget.icon),
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}