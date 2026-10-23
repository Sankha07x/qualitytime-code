import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Quoted message shown inside a bubble.
class QuoteBox extends StatelessWidget {
  final String name;
  final String text;
  final Color fg;
  const QuoteBox(
      {super.key, required this.name, required this.text, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: fg.withOpacity(0.15),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 3, color: fg),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        Text(text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: fg.withOpacity(0.85), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bar above the input: "Replying to ..." or "Editing message".
class ReplyBanner extends StatelessWidget {
  final String title;
  final String text;
  final bool editing;
  final VoidCallback onClose;
  const ReplyBanner({
    super.key,
    required this.title,
    required this.text,
    required this.editing,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: s.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(editing ? Icons.edit_outlined : Icons.reply,
              color: s.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: s.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close, size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Swipe a message to the right to reply to it.
class SwipeReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const SwipeReply({super.key, required this.child, required this.onReply});

  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> {
  double _dx = 0;
  bool _fired = false;

  void _reset() {
    _fired = false;
    if (_dx != 0) setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final v = (_dx + d.delta.dx).clamp(0.0, 64.0);
        if (v != _dx) setState(() => _dx = v);
        if (_dx >= 48 && !_fired) {
          _fired = true;
          HapticFeedback.mediumImpact();
          widget.onReply();
        }
      },
      onHorizontalDragEnd: (_) => _reset(),
      onHorizontalDragCancel: _reset,
      child: Stack(
        children: [
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: (_dx / 48).clamp(0.0, 1.0),
                child: const Icon(Icons.reply, size: 24),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// Text where links can be tapped.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const LinkText(this.text, {super.key, required this.style});

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  static final _re = RegExp(r'(https?://[^\s]+|www\.[^\s]+)');
  final _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  Future<void> _open(String url) async {
    try {
      final u = url.startsWith('http') ? url : 'https://$url';
      await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final t = widget.text;
    if (!_re.hasMatch(t)) return Text(t, style: widget.style);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _re.allMatches(t)) {
      if (m.start > at) spans.add(TextSpan(text: t.substring(at, m.start)));
      final url = m.group(0)!;
      final tap = TapGestureRecognizer()..onTap = () => _open(url);
      _taps.add(tap);
      spans.add(TextSpan(
        text: url,
        recognizer: tap,
        style: const TextStyle(
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600),
      ));
      at = m.end;
    }
    if (at < t.length) spans.add(TextSpan(text: t.substring(at)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}