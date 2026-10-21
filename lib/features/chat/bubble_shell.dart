import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';

String hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

Color bubbleFg(BuildContext context, bool mine) =>
    mine ? Colors.white : Theme.of(context).colorScheme.onSurface;

Color _darker(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - 0.12).clamp(0.0, 1.0)).toColor();
}

/// Shared bubble look for text, file and voice messages.
class BubbleShell extends StatelessWidget {
  final bool mine;
  final Widget child;
  final VoidCallback? onLongPress;

  const BubbleShell({
    super.key,
    required this.mine,
    required this.child,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final accent = Color(AppSettings.accent.value);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2.5),
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            gradient: mine
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, _darker(accent)],
                  )
                : null,
            color: mine ? null : s.surface.withOpacity(0.85),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
            border: mine
                ? null
                : Border.all(color: s.outlineVariant.withOpacity(0.6)),
          ),
          child: child,
        ),
      ),
    );
  }
}