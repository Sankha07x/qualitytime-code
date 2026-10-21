import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';
import 'typing_service.dart';

/// True when the text is only emojis (up to 6), so it can be shown big.
bool bigEmoji(String? s) {
  final t = (s ?? '').trim();
  if (t.isEmpty || t.runes.length > 6) return false;
  return t.runes.every((r) =>
      r == 0x20 ||
      r == 0x200D ||
      r == 0xFE0F ||
      r >= 0x1F000 ||
      (r >= 0x2600 && r <= 0x27BF));
}

/// Name with a small "typing…" / "online" line under it.
class ChatTitle extends StatelessWidget {
  final String name;
  final TypingService typing;
  const ChatTitle({super.key, required this.name, required this.typing});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final accent = Color(AppSettings.accent.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        AnimatedBuilder(
          animation: Listenable.merge([typing.typing, typing.online]),
          builder: (_, __) {
            final t = typing.typing.value;
            final text = t ? 'typing…' : (typing.online.value ? 'online' : '');
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: text.isEmpty
                  ? const SizedBox.shrink(key: ValueKey(''))
                  : Text(text,
                      key: ValueKey(text),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: t ? FontWeight.w600 : FontWeight.w400,
                          color: t ? accent : s.onSurfaceVariant)),
            );
          },
        ),
      ],
    );
  }
}

/// Bouncing three dots shown in the chat while the friend types.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _dot(int i, Color color) {
    final p = (_c.value - i * 0.15) % 1.0;
    final up = p < 0.5 ? math.sin(p * 2 * math.pi) : 0.0;
    return Transform.translate(
      offset: Offset(0, -5 * up),
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.45 + 0.55 * up),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 3, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: s.surface.withOpacity(0.85),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: s.outlineVariant),
        ),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (var i = 0; i < 3; i++) _dot(i, s.onSurface)],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Today" / "Yesterday" / "12 Oct 2026" heading between messages.
class DateChip extends StatelessWidget {
  final DateTime at;
  const DateChip(this.at, {super.key});

  String _label() {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(at.year, at.month, at.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${at.day} ${m[at.month - 1]} ${at.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: s.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_label(),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: s.onSurfaceVariant)),
        ),
      ),
    );
  }
}

/// Puts the scroll-to-bottom button above the message bar.
class DownFabLocation extends FloatingActionButtonLocation {
  const DownFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) => Offset(
        g.scaffoldSize.width - g.floatingActionButtonSize.width - 16,
        g.contentBottom - g.floatingActionButtonSize.height - 120,
      );
}